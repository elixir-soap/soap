defmodule Soap.Request do
  defstruct [:url, :headers, :body]
  @moduledoc """
  Documentation for Soap.Request.
  """

  def init_model(wsdl, globals) do
    %Soap.Request{
      url: wsdl[:endpoint],
      headers: globals.headers,
      body: globals.body
    }
  end
end
