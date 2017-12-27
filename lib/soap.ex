defmodule Soap do
  @moduledoc """
  Documentation for Soap.
  """

  import SweetXml

  def init_model(wsdl_path) do
    {:ok, wsdl} = File.read(wsdl_path)

    %{
      namespaces: parse_namespaces(wsdl),
      endpoint: parse_endpoint(wsdl),
      service_name: parse_service_name(wsdl),
      messages: parse_messages(wsdl),
      port_types: parse_port_types(wsdl),
      port_type_operations: parse_port_type_operations(wsdl),
      operations: parse_operations(wsdl),
      operations_parameters: parse_operations_parameters(wsdl),
      types: parse_types(wsdl),
      deferred_types: parse_deferred_types(wsdl)
    }
  end

  defp parse_namespaces(wsdl) do
    wsdl
    |> xpath(~x"//wsdl:definitions/namespace::*"l)
    |> Enum.map(&get_namespaces/1)
    |> Enum.into(%{})
  end

  defp get_namespaces(namespaces_node) do
    {_, _, _, key, value} = namespaces_node
    {key, value}
  end

  defp parse_endpoint(wsdl) do
    xpath(wsdl, ~x"//wsdl:definitions/wsdl:service/wsdl:port/soap:address/@location")
  end

  defp parse_service_name(wsdl) do
    xpath(wsdl, ~x"//@name")
  end

  defp parse_messages(wsdl) do
    xpath(wsdl, ~x"//*[local-name()='message']"l)
  end

  defp parse_port_types(wsdl) do
    xpath(wsdl, ~x"//wsdl:definitions/wsdl:portType"l, name: ~x"//@name", body: ~x"/")
  end

  defp parse_port_type_operations(wsdl) do
    xpath(wsdl, ~x"//wsdl:definitions/wsdl:portType"l,
    port_type: ~x"//@name", operations: ~x"//wsdl:operation/@name"l)
  end

  defp parse_operations(wsdl) do
    xpath(
      wsdl,
      ~x"//wsdl:definitions/wsdl:binding/wsdl:operation"l,
      operation: [~x".", name: ~x"@name", action: ~x"./soap:operation/@soapAction"]
    )
  end

  defp parse_operations_parameters(wsdl) do
    parse_operations(wsdl)
    |> Enum.map(fn(x) -> x[:operation][:name] end)
    |> Enum.map(fn(x) -> %{operation: x} |> Map.merge(extract_operation_parameters(wsdl, x)) end)
  end

  defp parse_types(wsdl) do
    {}
  end

  defp parse_deferred_types(wsdl) do
    {}
  end

  defp extract_operation_parameters(wsdl, name) do
    xpath(
      wsdl,
      ~x"//wsdl:definitions/wsdl:types/xsd:schema/xsd:complexType[@name='#{name}']",
      params: [~x"//xsd:element"l, name: ~x"//@name", type: ~x"//@type"]
    )
  end
end
