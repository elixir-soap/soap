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
    * `:port` - the name of the `wsdl:port` to use, when the WSDL offers the operation on
      several. It picks the binding and the address. Without it, the first port in the
      WSDL that offers the operation is used, after `:version` and `:input` narrow them.
    * `:version` - the SOAP version, `"1.1"` or `"1.2"`, when the WSDL offers both.
    * `:input` - the input's name, to choose between overloaded operations.
    * `:soap_headers` - SOAP headers, in the same forms as params.
    * `:http_headers` - extra HTTP headers. One with the name of a standard header
      replaces it.
    * `:wsse` - WS-Security credentials from `Soap.WSSE.username_token/3`.
    * `:mtom` - send every base64 field as an attachment.
    * `:attachments` - `Soap.Attachment` structs to send as extra parts.
    * `:validate` - check params against the schema. Defaults to true.
    * `:timeout` - how long to wait for a reply, in milliseconds.
    * `:connect_timeout` - how long to wait for a connection, in milliseconds.
    * `:follow_redirects` - follow HTTP redirects on calls. Defaults to false.
    * `:max_reply_size` - the largest reply to accept, in bytes, both as received and once
      decompressed. Defaults to 100 MB. `:infinity` turns it off.
    * `:http` - a `Soap.HTTP` implementation. Defaults to `Soap.HTTP.Req`.
    * `:http_opts` - extra options for that implementation.
    * `:telemetry_metadata` - a map added to telemetry events.

  A call's options replace the client's, except these, which are merged:

    * `:http_headers` - by name, ignoring case. The call's value wins, and a `nil` value
      removes the header, including a standard one such as `SOAPAction`.
    * `:soap_headers` - by name. The call's value wins, a `nil` value removes the header,
      and unnamed ones such as `%Soap.Raw{}` are added.
    * `:http_opts` - by key, and recursively for nested keyword lists such as `req: [...]`.
    * `:telemetry_metadata` - by key.

  `load/2` also takes the import options described in `Soap.Service`.

  See `Soap.Encoder` for the params format, `Soap.Decoder` for the result format, and
  `Soap.Telemetry` for events.
  """

  alias Soap.{Attachment, Client, Decoder, Encoder, Error, Fault, HTTP, Multipart, Request, Response, Service, WSSE}
  alias Soap.Options
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

  @doc "The names of the WSDL's ports, for the `:port` option."
  @spec ports(Client.t()) :: [String.t()]
  def ports(%Client{service: service}), do: Service.port_names(service)

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
    opts = Options.merge(client.opts, opts)

    with :ok <- validate(opts),
         {:ok, operation} <- find_operation(client, operation_name, opts),
         {:ok, request} <- build(client, operation, params, opts) do
      send_request(client, operation, request, opts)
    end
  end

  @doc "Builds a request without sending it."
  @spec build_request(Client.t(), String.t(), term(), keyword()) :: {:ok, Request.t()} | {:error, Error.t()}
  def build_request(%Client{} = client, operation_name, params \\ %{}, opts \\ []) do
    opts = Options.merge(client.opts, opts)

    with :ok <- validate(opts),
         {:ok, operation} <- find_operation(client, operation_name, opts) do
      build(client, operation, params, opts)
    end
  end

  @doc """
  Decodes a reply that arrived some other way.

  With a client and an operation name, the reply is decoded with that operation's schema,
  and an unknown name returns `{:unknown_operation, name, available}`. With a nil name,
  only the schema's global elements are used. With no client, nothing is.
  """
  @spec decode_response(Client.t() | nil, String.t() | nil, pos_integer(), list(), binary()) ::
          {:ok, Response.t()} | {:error, Fault.t() | Error.t()}
  def decode_response(client, operation_name, status, headers, body) do
    with {:ok, service, operation} <- decoding_context(client, operation_name),
         {:ok, decoded} <- decode(service, operation, {status, headers, body}, decoding_opts(client)) do
      {:ok, Response.new(status, headers, body, decoded)}
    end
  end

  defp decode(service, operation, {status, headers, body}, opts) do
    case Decoder.decode(service, operation, status, headers, body, opts) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, %Fault{} = fault} -> {:error, %{fault | status: fault.status || status, headers: headers, body: body}}
      {:error, %Error{} = error} -> {:error, %{error | status: status, headers: headers, body: body}}
    end
  end

  defp decoding_opts(nil), do: []
  defp decoding_opts(%Client{opts: opts}), do: Keyword.take(opts, [:max_reply_size])

  defp decoding_context(nil, _name), do: {:ok, nil, nil}
  defp decoding_context(%Client{service: service}, nil), do: {:ok, service, nil}

  defp decoding_context(%Client{service: service} = client, name) do
    with {:ok, operation} <- find_operation(client, name, client.opts), do: {:ok, service, operation}
  end

  defp validate(opts) do
    with {:error, reason} <- Options.validate(opts), do: {:error, %Error{reason: reason}}
  end

  defp find_operation(%Client{service: service}, name, opts) do
    case Service.operation(service, name, Keyword.take(opts, [:port, :version, :input])) do
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
         url: Keyword.get(opts, :endpoint) || Service.endpoint(service, operation, Keyword.get(opts, :port)),
         operation: operation.name,
         version: operation.version,
         body: body,
         attachments: attachments,
         headers: request_headers(operation, content_type, opts)
       }}
    end
  end

  defp encoder_opts(opts) do
    soap_headers = Options.soap_headers(Keyword.get(opts, :soap_headers, []))
    security = if opts[:wsse], do: [WSSE.header(opts[:wsse])], else: []
    [soap_headers: security ++ soap_headers] ++ Keyword.take(opts, [:mtom, :validate])
  end

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

  defp request_headers(operation, content_type, opts) do
    custom = Keyword.get(opts, :http_headers, [])
    custom = if content_type, do: [{"Content-Type", content_type} | custom], else: custom
    operation |> Request.headers(custom) |> Options.http_headers()
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
    limit = Decoder.max_reply_size(opts)

    http_opts =
      opts
      |> Keyword.get(:http_opts, [])
      |> Keyword.merge(Keyword.take(opts, @http_option_keys))
      |> Keyword.put(:max_reply_size, limit)

    case HTTP.adapter(opts).request(:post, request.url, request.headers, request.body, http_opts) do
      {:ok, %{status: status, headers: headers, body: body}} ->
        with {:ok, decoded} <- decode(service, operation, {status, headers, body}, max_reply_size: limit) do
          {:ok, Response.new(status, headers, body, decoded)}
        end

      {:error, :reply_too_large} ->
        {:error, %Error{reason: :reply_too_large}}

      {:error, reason} ->
        {:error, %Error{reason: {:transport, reason}}}
    end
  end
end
