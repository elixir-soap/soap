defmodule Soap.Request do
  @moduledoc """
  Documentation for Soap.Request.
  """
  alias Soap.Request.Params

  @doc """
  Executing with parsed wsdl and headers with body map.
  Calling HTTPoison request by Map with method, url, body, headers, options keys.
  """
  @spec call(wsdl :: map(), operation :: String.t(), params :: any(), headers :: any()) :: any()
  def call(wsdl, operation, params, headers \\ []) do
    url = Params.get_url(wsdl)
    headers = Params.build_headers(operation, headers)
    body = Params.build_body(wsdl, operation, params)

    HTTPoison.post!(url, body, headers)
  end
end
