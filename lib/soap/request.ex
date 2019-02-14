defmodule Soap.Request do
  @moduledoc """
  Documentation for Soap.Request.
  """
  alias Soap.Request.{Headers, Params}

  @doc """
  Executing with parsed wsdl and headers with body map.
  Calling HTTPoison request by Map with method, url, body, headers, options keys.
  """
  @spec call(wsdl :: map(), operation :: String.t(), params :: any(), headers :: any(), opts :: any()) :: any()
  def call(wsdl, operation, soap_headers_and_params, request_headers \\ [], opts \\ [])

  def call(wsdl, operation, {soap_headers, params}, request_headers, opts) do
    url = get_url(wsdl)
    request_headers = Headers.build(wsdl, operation, request_headers)
    body = Params.build_body(wsdl, operation, params, soap_headers)

    HTTPoison.post(url, body, request_headers, opts)
  end

  def call(wsdl, operation, params, request_headers, opts),
    do: call(wsdl, operation, {nil, params}, request_headers, opts)

  @spec get_url(wsdl :: map()) :: String.t()
  defp get_url(wsdl) do
    wsdl.endpoint
  end
end
