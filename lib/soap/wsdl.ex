defmodule Soap.Wsdl do
  @moduledoc """
  Provides functions for parsing wsdl file
  """

  import SweetXml, except: [parse: 1]

  @spec parse_from_file(String.t()) :: {:ok, map()}
  def parse_from_file(path) do
    {:ok, wsdl} = File.read(path)
    parse(wsdl)
  end

  @spec parse_from_url(String.t()) :: {:ok, map()}
  def parse_from_url(path) do
    %HTTPoison.Response{body: wsdl} = HTTPoison.get!(path, [], follow_redirect: true, max_redirect: 5)
    parse(wsdl)
  end

  @spec parse(String.t()) :: {:ok, map()}
  defp parse(wsdl) do
    protocol_namespace = get_protocol_namespace(wsdl)
    schema_namespace = get_schema_namespace(wsdl)

    parsed_response = %{
      namespaces: get_namespaces(wsdl, schema_namespace, protocol_namespace),
      endpoint: get_endpoint(wsdl, protocol_namespace),
      complex_types: get_complex_types(wsdl, schema_namespace, protocol_namespace),
      operations: get_operations(wsdl, protocol_namespace),
      schema_attributes: get_schema_attributes(wsdl, protocol_namespace)
    }

    {:ok, parsed_response}
  end

  @spec get_schema_namespace(String.t()) :: String.t()
  defp get_schema_namespace(wsdl) do
    {_, _, _, schema_namespace, _} =
      wsdl
      |> xpath(~x"//namespace::*"l)
      |> Enum.find(fn {_, _, _, _, x} -> x == :"http://www.w3.org/2001/XMLSchema" end)

    schema_namespace
  end

  @spec get_namespaces(String.t(), String.t(), String.t()) :: map()
  defp get_namespaces(wsdl, schema_namespace, protocol_ns) do
    wsdl
    |> xpath(~x"//#{protocol_ns}:definitions/namespace::*"l)
    |> Enum.map(&get_namespace(&1, wsdl, schema_namespace, protocol_ns))
    |> Enum.into(%{})
  end

  @spec get_namespace(map(), String.t(), String.t(), String.t()) :: tuple()
  defp get_namespace(namespaces_node, wsdl, schema_namespace, protocol_ns) do
    {_, _, _, key, value} = namespaces_node
    string_key = key |> to_string
    value = Atom.to_string(value)

    cond do
      xpath(wsdl, ~x"//#{protocol_ns}:definitions[@targetNamespace='#{value}']") ->
        {string_key, %{value: value, type: :wsdl}}

      xpath(
        wsdl,
        ~x"//#{protocol_ns}:types/#{schema_namespace}:schema/#{schema_namespace}:import[@namespace='#{value}']"
      ) ->
        {string_key, %{value: value, type: :xsd}}

      true ->
        {string_key, %{value: value, type: :soap}}
    end
  end

  @spec get_endpoint(String.t(), String.t()) :: String.t()
  defp get_endpoint(wsdl, protocol_ns) do
    wsdl
    |> xpath(~x"//#{protocol_ns}:definitions/#{protocol_ns}:service/#{protocol_ns}:port/soap:address/@location"s)
  end

  @spec get_complex_types(String.t(), String.t(), String.t()) :: list()
  defp get_complex_types(wsdl, namespace, protocol_ns) do
    xpath(
      wsdl,
      ~x"//#{protocol_ns}:types/#{namespace}:schema/#{namespace}:element"l,
      name: ~x"./@name"s,
      type: ~x"./@type"s
    )
  end

  @spec get_operations(String.t(), String.t()) :: list()
  defp get_operations(wsdl, protocol_ns), do: get_operations(wsdl, soap_version(), protocol_ns)

  @spec get_operations(String.t(), String.t(), String.t()) :: list()
  defp get_operations(wsdl, "1.2", protocol_ns) do
    wsdl
    |> xpath(
      ~x"//#{protocol_ns}:definitions/#{protocol_ns}:binding/#{protocol_ns}:operation"l,
      name: ~x"./@name"s,
      soap_action: ~x"./soap12:operation/@soapAction"s
    )
    |> Enum.reject(fn x -> x[:soap_action] == "" end)
    |> process_operations_extractor_result(wsdl)
  end

  defp get_operations(wsdl, _soap_version, protocol_ns) do
    wsdl
    |> xpath(
      ~x"//#{protocol_ns}:definitions/#{protocol_ns}:binding/#{protocol_ns}:operation"l,
      name: ~x"./@name"s,
      soap_action: ~x"./soap:operation/@soapAction"s
    )
    |> Enum.reject(fn x -> x[:soap_action] == "" end)
  end

  @spec get_protocol_namespace(String.t()) :: String.t()
  defp get_protocol_namespace(wsdl) do
    wsdl
    |> xpath(~x"//namespace::*"l)
    |> Enum.find(fn({_, _, _, _, url}) -> url == :"http://schemas.xmlsoap.org/wsdl/" end)
    |> elem(3)
  end

  @spec get_schema_attributes(String.t(), String.t()) :: map()
  defp get_schema_attributes(wsdl, protocol_ns) do
    wsdl
    |> xpath(
      ~x"//#{protocol_ns}:types/*[local-name() = 'schema']",
      target_namespace: ~x"./@targetNamespace"s,
      element_form_default: ~x"./@elementFormDefault"s
    )
  end

  @spec process_operations_extractor_result(list(), String.t()) :: list()
  defp process_operations_extractor_result([], wsdl), do: get_operations(wsdl, "1.1")
  defp process_operations_extractor_result(result, _wsdl), do: result

  defp soap_version, do: Application.fetch_env!(:soap, :globals)[:version]
end
