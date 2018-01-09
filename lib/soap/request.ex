defmodule Soap.Request do
  @moduledoc """
  Documentation for Soap.Request.
  """
  alias Soap.Request.Params

  @doc """
  Executing with parsed wsdl and headers with body map.
  Calling HTTPoison request by Map with method, url, body, headers, options keys.
  """
  @spec call(wsdl :: map(), soap_action :: String.t(), params :: map()) :: tuple()
  def call(wsdl, soap_action, params) do
    params = Params.build(wsdl, soap_action, params) |> Map.values

    HTTPoison.request!(params)
  end
end
