defmodule Soap.Xsd do
  @moduledoc """
  Provides functions for parsing xsd file
  # TODO: Implement in version 0.2
  """

  import SweetXml, except: [parse: 1]

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
      simple_types: get_simple_types(xsd),
      complex_types: Type.get_complex_types(xsd, "//xsd:schema/xsd:complexType")
    }
    {:ok, parsed_response}
  end

  @spec get_simple_types(String.t()) :: list()
  def get_simple_types(wsdl) do
    wsdl
    |> xpath(
      ~x"//xsd:schema/xsd:simpleType"l,
      name: ~x"./@name"s,
      restriction: [
        ~x"./xsd:restriction"o,
        base: ~x"./@base"s,
        min_inclusive: ~x"./xsd:minInclusive/@value"io,
        max_inclusive: ~x"./xsd:maxInclusive/@value"io,
        max_length: ~x"./xsd:maxLength/@value"io,
        total_digits: ~x"./xsd:totalDigits/@value"io,
        fraction_digits: ~x"./xsd:fractionDigits/@value"io,
        pattern: ~x"./xsd:pattern/@value"so,
        enumeration: ~x"./xsd:enumeration/@value"lso
      ],
      list: [
        ~x"./xsd:list"o,
        item_type: ~x"./@itemType"s
      ],
      union: [
        ~x"./xsd:union"o,
        types: ~x"./xsd:simpleType/xsd:restriction/@base"lo
      ]
    )
  end
end
