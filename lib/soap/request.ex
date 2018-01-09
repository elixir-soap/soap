defmodule Soap.Request do
  defstruct [:method, :url, :body, :headers, :options]
  @moduledoc """
  Documentation for Soap.Request.
  """

  def init_model(wsdl, method \\ :post, %Soap.Request.Options{} = parameters, options) do
    %Soap.Request{
      url: wsdl[:endpoint],
      headers: parameters.headers,
      body: parameters.body,
      method: method,
      options: options
    }
  end

  def call(%Soap.Request{} = soap_request) do
    HTTPoison.request!(soap_request)
  end
end
