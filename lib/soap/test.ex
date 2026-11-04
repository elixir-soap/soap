defmodule Soap.Test do
  @moduledoc """
  Helpers for testing code that calls SOAP services, with no network.

      {:ok, client} =
        Soap.Test.client("priv/calculator.wsdl", fn request ->
          assert request.operation == "Add"
          assert request.params == %{"intA" => "2", "intB" => "3"}
          Soap.Test.reply("AddResponse", %{"AddResult" => 5}, namespace: "http://tempuri.org/")
        end)

      assert {:ok, %{"AddResponse" => %{"AddResult" => 5}}} = MyApp.add(client, 2, 3)

  The function gets a map with `:url`, `:headers`, `:body`, `:operation`, `:params`,
  `:soap_headers` and `:attachments`. `:operation` is the name of the Body's first
  element, and `:params` is its content. Values in `:params` are strings, because this
  side has no schema.

  It returns one of:

    * a binary - the body of an HTTP 200 reply
    * `{status, body}` or `{status, headers, body}`
    * `{:error, reason}` - a transport failure, such as `{:error, :timeout}`

  `reply/3`, `fault/3` and `envelope/2` build reply bodies.
  """
  @behaviour Soap.HTTP

  alias Soap.{Decoder, Encoder}

  @env11 "http://schemas.xmlsoap.org/soap/envelope/"
  @env12 "http://www.w3.org/2003/05/soap-envelope"

  @doc "Loads a WSDL and returns a client that answers with `handler` instead of the network."
  @spec client(String.t(), (map() -> term()), keyword()) :: {:ok, Soap.Client.t()} | {:error, Soap.Error.t()}
  def client(wsdl_path, handler, opts \\ []) do
    Soap.load(wsdl_path, Keyword.merge([http: __MODULE__, http_opts: [handler: handler]], opts))
  end

  @doc "Wraps XML in a SOAP envelope. Takes `:version`, which defaults to `\"1.1\"`."
  @spec envelope(iodata(), keyword()) :: binary()
  def envelope(inner, opts \\ []) do
    ns = if opts[:version] == "1.2", do: @env12, else: @env11
    IO.iodata_to_binary([~s(<e:Envelope xmlns:e="), ns, ~s("><e:Body>), inner, "</e:Body></e:Envelope>"])
  end

  @doc """
  Builds a reply whose Body holds one element made from plain data.

  Maps become child elements, lists repeat them, and `"@name"` keys become attributes.

  ## Options

    * `:namespace` - the root element's namespace.
    * `:version` - the SOAP version, which defaults to `"1.1"`.
  """
  @spec reply(String.t(), term(), keyword()) :: binary()
  def reply(name, value, opts \\ []) do
    {attrs, inner} = element_parts(value)
    namespace = if opts[:namespace], do: [~s( xmlns="), Encoder.escape_text(opts[:namespace]), ~s(")], else: []
    envelope(["<", name, namespace, attrs, ">", inner, "</", name, ">"], opts)
  end

  @doc """
  Builds a reply holding a SOAP Fault.

  Returns `{500, body}`. Takes `:version`, and with version 1.2 `code` is a Code value
  such as `"e:Sender"`.
  """
  @spec fault(String.t(), String.t(), keyword()) :: {500, binary()}
  def fault(code, message, opts \\ []) do
    text = Encoder.escape_text(message)

    inner =
      if opts[:version] == "1.2" do
        [
          "<e:Fault><e:Code><e:Value>",
          code,
          "</e:Value></e:Code><e:Reason><e:Text>",
          text,
          "</e:Text></e:Reason></e:Fault>"
        ]
      else
        ["<e:Fault><faultcode>", code, "</faultcode><faultstring>", text, "</faultstring></e:Fault>"]
      end

    {500, envelope(inner, opts)}
  end

  defp element_parts(value) when is_map(value) do
    {attrs, children} = Enum.split_with(value, fn {key, _} -> String.starts_with?(to_string(key), "@") end)

    attr_text =
      Enum.map(attrs, fn {key, v} -> [" ", String.trim_leading(to_string(key), "@"), ~s(="), text(v), ~s(")] end)

    {attr_text, Enum.map(children, &child/1)}
  end

  defp element_parts(nil), do: {[], []}
  defp element_parts(value), do: {[], text(value)}

  defp child({"#text", value}), do: text(value)

  defp child({key, values}) when is_list(values), do: Enum.map(values, &child({key, &1}))

  defp child({key, value}) do
    {attrs, inner} = element_parts(value)
    ["<", to_string(key), attrs, ">", inner, "</", to_string(key), ">"]
  end

  defp text(value), do: value |> to_string() |> Encoder.escape_text()

  @impl true
  def request(_method, url, headers, body, opts) do
    handler = Keyword.fetch!(opts, :handler)
    body = IO.iodata_to_binary(body)
    normalize(handler.(describe(url, headers, body)))
  end

  defp describe(url, headers, body) do
    decoded = Decoder.decode(nil, nil, 200, headers, body)

    {operation, params, soap_headers, attachments} =
      case decoded do
        {:ok, %{result: result, soap_headers: soap_headers, attachments: attachments}} when is_map(result) ->
          {name, value} = result |> Enum.to_list() |> List.first({nil, nil})
          {name, value, soap_headers, attachments}

        _ ->
          {nil, nil, %{}, []}
      end

    %{
      url: url,
      headers: headers,
      body: body,
      operation: operation,
      params: params,
      soap_headers: soap_headers,
      attachments: attachments
    }
  end

  defp normalize({:error, _} = error), do: error
  defp normalize({status, body}), do: {:ok, %{status: status, headers: [{"content-type", "text/xml"}], body: body}}
  defp normalize({status, headers, body}), do: {:ok, %{status: status, headers: headers, body: body}}
  defp normalize(body) when is_binary(body), do: normalize({200, body})
end
