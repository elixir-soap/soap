defmodule Soap.Request do
  defstruct [:method, :url, :body, :headers, :options]
  @moduledoc """
  Documentation for Soap.Request.
  """

  def init_model(wsdl, %{headers: headers, body: body}) do
    %Soap.Request{
      url: wsdl[:endpoint],
      headers: headers,
      body: body,
      method: :post,
      options: nil
    }
  end

  @doc """
  Executing with parsed wsdl and headers with body map.
  Calling httpoison request by Map with method, url, body, headers, options keys.
  """
  def call(wsdl, %{headers: headers, body: body}) do
    params = init_model(wsdl, %{headers: headers, body: body}) |> Map.values

    HTTPoison.request!(params)
  end
end
