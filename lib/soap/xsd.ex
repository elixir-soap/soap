defmodule Soap.Xsd do
  @moduledoc """
  Provides functions for parsing xsd file
  """

  import SweetXml, except: [parse: 1]

  def parse_from_file(path) do
    {:ok, wsdl} = File.read(path)
    parse(wsdl)
  end

  def parse(wsdl) do
    %{}
  end
end
