defmodule Soap do
  @moduledoc """
  A SOAP client for Elixir.

      {:ok, client} = Soap.load("https://example.com/calculator?wsdl")

      Soap.operations(client)
      #=> ["Add", "Subtract"]

      Soap.call(client, "Add", %{"intA" => 2, "intB" => 3})
      #=> {:ok, %{"AddResponse" => %{"AddResult" => 5}}}

  Everything is configured per client or per call. The library reads no application
  configuration, so one application can call any number of services, in either SOAP
  version.

  ## Client and call options

  These work in `load/2` and `from_string/2`, as defaults for the client, and in each call.

    * `:endpoint` - send here instead of the address in the WSDL.
    * `:version` - the SOAP version, `"1.1"` or `"1.2"`, when the WSDL offers both.
    * `:input` - the input's name, to choose between overloaded operations.
    * `:headers` - SOAP headers, in the same forms as params.
    * `:http_headers` - extra HTTP headers. One with the name of a standard header
      replaces it.
    * `:wsse` - WS-Security credentials from `Soap.WSSE.username_token/3`.
    * `:mtom` - send every base64 field as an attachment.
    * `:attachments` - `Soap.Attachment` structs to send as extra parts.
    * `:validate` - check params against the schema. Defaults to true.
    * `:timeout` - how long to wait for a reply, in milliseconds.
    * `:connect_timeout` - how long to wait for a connection, in milliseconds.
    * `:follow_redirects` - follow HTTP redirects on calls. Defaults to false.
    * `:http` - a `Soap.HTTP` implementation. Defaults to `Soap.HTTP.Req`.
    * `:http_opts` - extra options for that implementation.
    * `:telemetry_metadata` - a map added to telemetry events.

  `load/2` also takes the import options described in `Soap.Service`.

  See `Soap.Encoder` for the params format, `Soap.Decoder` for the result format, and
  `Soap.Telemetry` for events.
  """

  alias Soap.{Attachment, Client, Decoder, Encoder, Error, Fault, HTTP, Multipart, Request, Response, Service, WSSE}
  alias Soap.Service.Operation

  @typedoc "What a call returns."
  @type result :: {:ok, term()} | {:error, Fault.t() | Error.t()}

  @http_option_keys [:timeout, :connect_timeout, :follow_redirects]

  @doc "Loads a WSDL from a file path or URL, and returns a client."
  @spec load(String.t(), keyword()) :: {:ok, Client.t()} | {:error, Error.t()}
  def load(source, opts \\ []) do
    case Service.load(source, opts) do
      {:ok, service} -> {:ok, new(service, opts)}
      {:error, reason} -> {:error, %Error{reason: reason}}
    end
  end

  @doc "Reads a WSDL from a string, and returns a client."
  @spec from_string(binary(), keyword()) :: {:ok, Client.t()} | {:error, Error.t()}
  def from_string(wsdl, opts \\ []) do
    case Service.from_string(wsdl, opts) do
      {:ok, service} -> {:ok, new(service, opts)}
      {:error, reason} -> {:error, %Error{reason: reason}}
    end
  end

  @doc "Makes a client from a service that's already loaded."
  @spec new(Service.t(), keyword()) :: Client.t()
  def new(%Service{} = service, opts \\ []), do: %Client{service: service, opts: opts}

  @doc "The operations a client can call."
  @spec operations(Client.t()) :: [String.t()]
  def operations(%Client{service: service}), do: Service.operations(service)

  @doc """
  Calls an operation and returns its decoded result.

  A SOAP Fault returns `{:error, %Soap.Fault{}}`. Anything else that goes wrong returns
  `{:error, %Soap.Error{}}`.
  """
  @spec call(Client.t(), String.t(), term(), keyword()) :: result()
  def call(%Client{} = client, operation, params \\ %{}, opts \\ []) do
    with {:ok, response} <- request(client, operation, params, opts), do: {:ok, response.result}
  end

  @doc "Like `call/4`, but raises on a Fault or an error."
  @spec call!(Client.t(), String.t(), term(), keyword()) :: term()
  def call!(%Client{} = client, operation, params \\ %{}, opts \\ []) do
    case call(client, operation, params, opts) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Calls an operation and returns the whole `Soap.Response`: the HTTP status and headers,
  the raw body, the result, SOAP headers and attachments.
  """
  @spec request(Client.t(), String.t(), term(), keyword()) :: {:ok, Response.t()} | {:error, Fault.t() | Error.t()}
  def request(%Client{} = client, operation_name, params \\ %{}, opts \\ []) do
    opts = Keyword.merge(client.opts, opts)

    with {:ok, operation} <- find_operation(client, operation_name, opts),
         {:ok, request} <- build(client, operation, params, opts) do
      send_request(client, operation, request, opts)
    end
  end

  @doc "Builds a request without sending it."
  @spec build_request(Client.t(), String.t(), term(), keyword()) :: {:ok, Request.t()} | {:error, Error.t()}
  def build_request(%Client{} = client, operation_name, params \\ %{}, opts \\ []) do
    opts = Keyword.merge(client.opts, opts)

    with {:ok, operation} <- find_operation(client, operation_name, opts) do
      build(client, operation, params, opts)
    end
  end

  @doc "Decodes a reply that arrived some other way. `operation_name` can be nil."
  @spec decode_response(Client.t() | nil, String.t() | nil, pos_integer(), list(), binary()) ::
          {:ok, Response.t()} | {:error, Fault.t() | Error.t()}
  def decode_response(client, operation_name, status, headers, body) do
    {service, operation} = decoding_context(client, operation_name)

    with {:ok, decoded} <- Decoder.decode(service, operation, status, headers, body) do
      {:ok, Response.new(status, headers, body, decoded)}
    end
  end

  defp decoding_context(nil, _name), do: {nil, nil}
  defp decoding_context(%Client{service: service}, nil), do: {service, nil}

  defp decoding_context(%Client{service: service, opts: opts}, name) do
    case Service.operation(service, name, Keyword.take(opts, [:version, :input])) do
      {:ok, operation} -> {service, operation}
      {:error, _} -> {service, nil}
    end
  end

  defp find_operation(%Client{service: service}, name, opts) do
    case Service.operation(service, name, Keyword.take(opts, [:version, :input])) do
      {:ok, operation} -> {:ok, operation}
      {:error, reason} -> {:error, %Error{reason: reason}}
    end
  end

  defp build(%Client{service: service}, %Operation{} = operation, params, opts) do
    with {:ok, encoded} <- Encoder.encode(service, operation, params, encoder_opts(opts)) do
      attachments = encoded.attachments ++ extra_attachments(opts)
      {content_type, body} = packaged(encoded.xml, attachments, operation)

      {:ok,
       %Request{
         url: Keyword.get(opts, :endpoint) || Service.endpoint(service, operation),
         operation: operation.name,
         version: operation.version,
         body: body,
         attachments: attachments,
         headers: request_headers(operation, content_type, opts)
       }}
    end
  end

  defp encoder_opts(opts) do
    soap_headers = normalize_headers(Keyword.get(opts, :headers, []))
    security = if opts[:wsse], do: [WSSE.header(opts[:wsse])], else: []
    [headers: security ++ soap_headers] ++ Keyword.take(opts, [:mtom, :validate])
  end

  defp normalize_headers(headers) when is_map(headers), do: Enum.to_list(headers)
  defp normalize_headers(headers), do: headers

  defp extra_attachments(opts) do
    opts
    |> Keyword.get(:attachments, [])
    |> Enum.with_index(1)
    |> Enum.map(fn {%Attachment{} = attachment, index} -> %{attachment | id: attachment.id || "extra#{index}@soap"} end)
  end

  defp packaged(xml, [], _operation), do: {nil, xml}

  defp packaged(xml, attachments, %Operation{version: version}) do
    Multipart.build(xml, attachments, if(version == "1.1", do: "text/xml", else: "application/soap+xml"))
  end

  defp request_headers(operation, nil, opts), do: Request.headers(operation, Keyword.get(opts, :http_headers, []))

  defp request_headers(operation, content_type, opts) do
    custom = Keyword.get(opts, :http_headers, [])
    Request.headers(operation, [{"Content-Type", content_type} | custom])
  end

  defp send_request(_client, _operation, %Request{url: url}, _opts) when url in [nil, ""] do
    {:error, %Error{reason: :no_endpoint}}
  end

  defp send_request(client, operation, %Request{} = request, opts) do
    metadata = Soap.Telemetry.metadata(request, opts)

    :telemetry.span([:soap, :request], metadata, fn ->
      result = transmit(client, operation, request, opts)
      {result, Soap.Telemetry.stop_metadata(metadata, result)}
    end)
  end

  defp transmit(%Client{service: service}, operation, %Request{} = request, opts) do
    http_opts = Keyword.merge(Keyword.get(opts, :http_opts, []), Keyword.take(opts, @http_option_keys))

    case HTTP.adapter(opts).request(:post, request.url, request.headers, request.body, http_opts) do
      {:ok, %{status: status, headers: headers, body: body}} ->
        with {:ok, decoded} <- Decoder.decode(service, operation, status, headers, body) do
          {:ok, Response.new(status, headers, body, decoded)}
        end

      {:error, reason} ->
        {:error, %Error{reason: {:transport, reason}}}
    end
  end
end
