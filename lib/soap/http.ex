defmodule Soap.HTTP do
  @moduledoc """
  The HTTP client behaviour. Choose an implementation with the `:http` option.

  `Soap.HTTP.Req` is the default. To use another client, implement this behaviour, which
  takes a few lines. The README has an example for HTTPoison.

  A request returns `{:ok, %{status: integer, headers: list, body: binary}}` for any HTTP
  response, whatever its status, and `{:error, reason}` when there is no response.

  Implementations should understand these options, and pass through any others:

    * `:timeout` - how long to wait for a reply, in milliseconds.
    * `:connect_timeout` - how long to wait for a connection, in milliseconds.
    * `:follow_redirects` - whether to follow redirects.
  """

  @type response :: %{status: pos_integer(), headers: [{String.t(), String.t()}], body: binary()}

  @callback request(
              method :: :get | :post,
              url :: String.t(),
              headers :: [{String.t(), String.t()}],
              body :: iodata(),
              opts :: keyword()
            ) :: {:ok, response()} | {:error, term()}

  @doc "The implementation selected by `opts`."
  def adapter(opts), do: Keyword.get(opts, :http, Soap.HTTP.Req)
end

defmodule Soap.HTTP.Req do
  @moduledoc """
  An adapter for `Req`, the default.

  Pass Req options with `http_opts: [req: [...]]`. Compression and body decoding stay off,
  because `Soap.Decoder` handles the raw reply itself.
  """
  @behaviour Soap.HTTP

  @impl true
  def request(method, url, headers, body, opts) do
    base = [
      method: method,
      url: url,
      headers: headers,
      body: IO.iodata_to_binary(body),
      raw: true,
      retry: false,
      redirect: Keyword.get(opts, :follow_redirects, false)
    ]

    case Req.request(base ++ timeouts(opts) ++ Keyword.get(opts, :req, [])) do
      {:ok, %Req.Response{status: status, headers: response_headers, body: response_body}} ->
        {:ok, %{status: status, headers: flatten_headers(response_headers), body: response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp timeouts(opts) do
    receive_timeout = if opts[:timeout], do: [receive_timeout: opts[:timeout]], else: []
    connect = if opts[:connect_timeout], do: [connect_options: [timeout: opts[:connect_timeout]]], else: []
    receive_timeout ++ connect
  end

  defp flatten_headers(headers) do
    Enum.flat_map(headers, fn {name, values} -> Enum.map(List.wrap(values), &{name, &1}) end)
  end
end
