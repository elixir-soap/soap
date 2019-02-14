defmodule Soap.Xsd do
  @moduledoc """
  Provides functions for parsing xsd file
  """

  import SweetXml, except: [parse: 1]

  alias Soap.Type

  @spec parse(String.t()) :: {:ok, map()} | {:error, atom()}
  def parse(path) do
    if URI.parse(path).scheme do
      parse_from_url(path)
    else
      parse_from_file(path)
    end
  end

  @spec parse_from_file(String.t()) :: {:ok, map()} | {:error, atom()}
  def parse_from_file(path) do
    case File.read(path) do
      {:ok, xsd} -> parse_xsd(xsd)
      error_response -> error_response
    end
  end

  @spec parse_from_url(String.t()) :: {:ok, map()} | {:error, atom()}
  def parse_from_url(path) do
    case HTTPoison.get(path, [], follow_redirect: true, max_redirect: 5) do
      {:ok, %HTTPoison.Response{status_code: 404}} -> {:error, :not_found}
      {:ok, %HTTPoison.Response{body: body}} -> parse_xsd(body)
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end
  end

  @spec parse(String.t()) :: {:ok, map()}
  defp parse_xsd(xsd) do
    parsed_response = %{
      simple_types: get_simple_types(xsd),
      complex_types: Type.get_complex_types(xsd, "//xsd:schema/xsd:complexType")
    }

    {:ok, parsed_response}
  end

  @spec get_simple_types(String.t()) :: list()
  defp get_simple_types(wsdl) do
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
