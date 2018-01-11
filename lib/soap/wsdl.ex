defmodule Soap.Wsdl do
  @moduledoc """
  Provides functions for parsing wsdl file
  """

  import SweetXml, except: [parse: 1]

  def parse_from_file(path) do
    {:ok, wsdl} = File.read(path)
    parse(wsdl)
  end

  def parse_from_url(path) do
    %HTTPoison.Response{body: wsdl} = HTTPoison.get!(path)
    parse(wsdl)
  end

  def parse(wsdl) do
    {:ok, wsdl}
  end

  def get_namespaces(wsdl) do
    wsdl
    |> xpath(~x"//wsdl:definitions/namespace::*"l)
    |> Enum.map(&get_namespace(&1, wsdl))
    |> Enum.into(%{})
  end

  defp get_namespace(namespaces_node, wsdl) do
    {_, _, _, key, value} = namespaces_node
    value = Atom.to_string(value)

    cond do
      xpath(wsdl, ~x"//wsdl:definitions[@targetNamespace='#{value}']") ->
        {key, %{value: value, type: :wsdl}}
      xpath(wsdl, ~x"//wsdl:types/xsd:schema/xsd:import[@namespace='#{value}']") ->
        {key, %{value: value, type: :xsd}}
      true ->
        {key, %{value: value, type: :soap}}
    end
  end

  def get_endpoint(wsdl) do
    xpath(wsdl, ~x"//wsdl:definitions/wsdl:service/wsdl:port/soap:address/@location")
  end

  def get_messages(wsdl) do
    xpath(wsdl, ~x"//*[local-name()='message']"l)
  end

  def get_port_types(wsdl) do
    xpath(wsdl, ~x"//wsdl:definitions/wsdl:portType"l, name: ~x"//@name", body: ~x"/")
  end

  def get_port_type_operations(wsdl) do
    xpath(
      wsdl,
      ~x"//wsdl:definitions/wsdl:portType"l,
      port_type: ~x"//@name",
      operations: ~x"//wsdl:operation/@name"l
    )
  end

  def parse_operations(wsdl) do
    xpath(
      wsdl,
      ~x"//wsdl:definitions/wsdl:binding/wsdl:operation"l,
      operation: [~x".", name: ~x"@name", action: ~x"./soap:operation/@soapAction"]
    )
  end

  def parse_operations_parameters(wsdl) do
    wsdl
    |> parse_operations
    |> Enum.map(&extract_operation_parameters(wsdl, &1))
  end

  # def parse_types(wsdl) do
  #   compex_types = get_compex_types(wsdl)
  #   compex_types
  #   |> Enum.map(&get_root_elements(&1, wsdl))
  # end

  # def get_root_elements(complex_type, wsdl) do
  #   elements = xpath(
  #     wsdl,
  #     ~x"//xsd:complexType[@name='#{complex_type.name}']/xsd:sequence/xsd:element"l, name: ~x"./@name", type: ~x"./@type", complex_type: ~x"local-name()"
  #   )
  #   |> Enum.map(&get_types/1)
  #
  #   %{
  #     name: complex_type.name,
  #     type: complex_type.type,
  #     elements: elements
  #   }
  # end

  def get_complex_types(wsdl) do
    xpath(wsdl, ~x"//wsdl:types/xsd:schema/xsd:element"l, name: ~x"./@name"s, type: ~x"./@type"s)
  end

  def extract_operation_parameters(wsdl, %{operation: %{name: name}} = _operation) do
    wsdl
    |> xpath(
      ~x"//wsdl:definitions/wsdl:types/xsd:schema/xsd:complexType[@name='#{name}']",
      params: [~x"//xsd:element"l, name: ~x"//@name", type: ~x"//@type"])
    |> Map.merge(%{operation: name})
  end
end
