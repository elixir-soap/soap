defmodule Soap do
  @moduledoc """
  Documentation for Soap.
  """

  alias Soap.Wsdl

  def init_model(path, type \\ :file)
  def init_model(path, :file) do
    {:ok, wsdl} = Wsdl.parse_from_file(path)
    wsdl
  end
  def init_model(path, :url) do
    {:ok, wsdl} = Wsdl.parse_from_url(path)
    wsdl
  end
end
