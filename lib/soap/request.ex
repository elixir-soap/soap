defmodule Soap.Request do
  @moduledoc """
  Documentation for Soap.Request.
  """

  @spec build(wsdl :: String.t(), %{headers: headers :: String.t(), body: body :: String.t()}) :: map()
  def build(wsdl, %{headers: headers, body: body}) do
    %{
      url: wsdl[:endpoint],
      headers: headers,
      body: body,
      method: :post,
      options: nil
    }
  end

  @doc """
  Executing with parsed wsdl and headers with body map.
  Calling HTTPoison request by Map with method, url, body, headers, options keys.
  """
  @spec call(wsdl :: String.t(), %{headers: headers :: String.t(), body: body :: String.t()}) :: tuple()
  def call(wsdl, %{headers: headers, body: body}) do
    params = build(wsdl, %{headers: headers, body: body}) |> Map.values

    HTTPoison.request!(params)
  end
end
