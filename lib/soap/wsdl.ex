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
    %HTTPoison.Response{body: wsdl} = HTTPoison.get!(path, [], [follow_redirect: true, max_redirect: 5])
    parse(wsdl)
  end

  @spec parse(String.t()) :: {:ok, map()}
  def parse(wsdl) do
    parsed_response = %{
      namespaces: get_namespaces(wsdl),
      endpoint: get_endpoint(wsdl),
      complex_types: get_complex_types(wsdl),
      operations: get_operations(wsdl)
    }
    {:ok, parsed_response}
  end

  @spec get_namespaces(String.t()) :: map()
  def get_namespaces(wsdl) do
    wsdl
    |> xpath(~x"//wsdl:definitions/namespace::*"l)
    |> Enum.map(&get_namespace(&1, wsdl))
    |> Enum.into(%{})
  end

  defp get_namespace(namespaces_node, wsdl) do
    {_, _, _, key, value} = namespaces_node
    string_key = key |> to_string
    value = Atom.to_string(value)

    cond do
      xpath(wsdl, ~x"//wsdl:definitions[@targetNamespace='#{value}']") ->
        {string_key, %{value: value, type: :wsdl}}
      xpath(wsdl, ~x"//wsdl:types/xsd:schema/xsd:import[@namespace='#{value}']") ->
        {string_key, %{value: value, type: :xsd}}
      true ->
        {string_key, %{value: value, type: :soap}}
    end
  end

  @spec get_endpoint(String.t()) :: String.t()
  def get_endpoint(wsdl) do
    wsdl
    |> xpath(~x"//wsdl:definitions/wsdl:service/wsdl:port/soap:address/@location"s)
  end

  @spec get_complex_types(String.t()) :: list()
  def get_complex_types(wsdl) do
    xpath(wsdl, ~x"//wsdl:types/xsd:schema/xsd:element"l, name: ~x"./@name"s, type: ~x"./@type"s)
  end

  def get_operations(wsdl) do
    soap_version = Application.fetch_env!(:soap, :globals)[:version]
    get_operations(wsdl, soap_version)
  end

  defp get_operations(wsdl, "1.2") do
    wsdl
    |> xpath(
      ~x"//wsdl:definitions/wsdl:binding/wsdl:operation"l,
      name: ~x"./@name"s,
      soap_action: ~x"./soap12:operation/@soapAction"s
    )
    |> Enum.reject(fn x -> x[:soap_action] == "" end)
    |> process_operations_extractor_result(wsdl)
  end

  defp get_operations(wsdl, "1.1") do
    wsdl
    |> xpath(
      ~x"//wsdl:definitions/wsdl:binding/wsdl:operation"l,
      name: ~x"./@name"s,
      soap_action: ~x"./soap:operation/@soapAction"s
    )
    |> Enum.reject(fn x -> x[:soap_action] == "" end)
  end

  defp process_operations_extractor_result(result, wsdl) when result == [] do
    wsdl |> get_operations("1.1")
  end

  defp process_operations_extractor_result(result, _wsdl), do: result
end
