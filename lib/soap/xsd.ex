defmodule Soap.Xsd do
  @moduledoc """
  Provides functions for parsing xsd file
  # TODO: Implement in version 0.2
  """

  alias Soap.Type

  @spec parse_from_file(String.t()) :: {:ok, map()} | {:error, atom()}
  def parse_from_file(path) do
    case File.read(path) do
      {:ok, xsd} -> parse(xsd)
      error_response -> error_response
    end
  end

  @spec parse(String.t()) :: {:ok, map()}
  def parse(xsd) do
    parsed_response = %{
      complex_types: Type.get_complex_types(xsd, "//xsd:schema/xsd:complexType")
    }
    {:ok, parsed_response}
  end
end
