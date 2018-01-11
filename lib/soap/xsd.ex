defmodule Soap.Xsd do
  @moduledoc """
  Provides functions for parsing xsd file
  # TODO: Implement in version 0.2
  """

  def parse_from_file(path) do
    {:ok, wsdl} = File.read(path)
    parse(wsdl)
  end

  def parse(wsdl) do
    wsdl
  end
end
