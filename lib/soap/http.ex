defmodule Soap.HTTP do
  @moduledoc """
  The HTTP client behaviour. Pass an implementation with the `:http` option.

  A request returns `{:ok, %{status: integer, headers: list, body: binary}}` for any
  HTTP response, whatever its status, and `{:error, reason}` when there is no response.
  """

  @type response :: %{status: pos_integer(), headers: [{String.t(), String.t()}], body: binary()}

  @callback request(
              method :: :get | :post,
              url :: String.t(),
              headers :: [{String.t(), String.t()}],
              body :: iodata(),
              opts :: keyword()
            ) :: {:ok, response()} | {:error, term()}

  @doc "The adapter selected by `opts`."
  def adapter(opts), do: Keyword.get(opts, :http, Soap.HTTP.HTTPoison)
end

defmodule Soap.HTTP.HTTPoison do
  @moduledoc "An adapter for `HTTPoison`."
  @behaviour Soap.HTTP

  @impl true
  def request(method, url, headers, body, opts) do
    case HTTPoison.request(method, url, IO.iodata_to_binary(body), headers, opts) do
      {:ok, %HTTPoison.Response{status_code: status, headers: response_headers, body: response_body}} ->
        {:ok, %{status: status, headers: response_headers, body: response_body}}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end
end
