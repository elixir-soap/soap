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
    {}
  end

  defp parse_endpoint(wsdl) do
    {}
  end

  defp parse_service_name(wsdl) do
    {}
  end

  defp parse_messages(wsdl) do
    {}
  end

  defp parse_port_types(wsdl) do
    {}
  end

  defp parse_port_type_operations(wsdl) do
    {}
  end

  defp parse_operations(wsdl) do
    xpath(
      wsdl,
      ~x"//wsdl:definitions/wsdl:binding/wsdl:operation"l,
      [operation: [~x".", name: ~x"@name", action: ~x"./soap:operation/@soapAction"]]
    )
  end

  defp parse_operations_parameters(wsdl) do
    {}
  end

  defp parse_types(wsdl) do
    {}
  end

  defp parse_deferred_types(wsdl) do
    {}
  end

end
