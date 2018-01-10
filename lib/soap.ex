defmodule Soap do
  @moduledoc """
  Documentation for Soap.
  """

  alias Soap.Wsdl
  alias Soap.Request

  @spec init_model(String.t(), :file | :url) :: map()
  def init_model(path, type \\ :file)
  def init_model(path, :file) do
    {:ok, wsdl} = Wsdl.parse_from_file(path)
    wsdl
  end
  def init_model(path, :url) do
    {:ok, wsdl} = Wsdl.parse_from_url(path)
    wsdl
  end

  def call(wsdl, soap_action, params) do
    Request.call(wsdl, soap_action, params)
  end
end
