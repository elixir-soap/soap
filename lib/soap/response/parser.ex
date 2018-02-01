defmodule Soap.Response.Parser do
  @moduledoc """
  Provides a functions for parse an xml-like response body.
  """

  import SweetXml, only: [xpath: 2, sigil_x: 2]

  @soap_version_namespaces %{
    "1.1" => "http://schemas.xmlsoap.org/soap/envelope/",
    "1.2" => "http://www.w3.org/2003/05/soap-envelope"
  }
  @doc """
  Executing with xml response body.
  If a list is empty then parse/1 returns full parsed response structure into map.
  """
  @spec parse(String.t(), integer()) :: map()
  def parse(xml_response, status_code) when status_code >= 400 do
    fault_tag = get_fault_tag(xml_response)

    xml_response
    |> xpath(~x"//#{fault_tag}/*"l)
    |> parse_elements
  end

  def parse(xml_response, _status_code) do
    xml_response
    |> xpath(~x"//response/*"l)
    |> parse_elements
  end

  @spec parse_record(tuple()) :: map() | String.t()
  defp parse_record({:xmlElement, tag_name, _, _, _, _, _, _, elements, _, _, _}) do
    %{tag_name => parse_elements(elements)}
  end

  defp parse_record({:xmlText, _, _, _, value, _}) when is_list(value), do: List.to_string(value)
  defp parse_record({:xmlText, _, _, _, value, _}) when is_binary(value), do: value

  @spec parse_elements(list() | tuple()) :: map()
  defp parse_elements([]), do: %{}
  defp parse_elements(elements) when is_tuple(elements), do: parse_record(elements)

  defp parse_elements(elements) when is_list(elements) do
    elements
    |> Enum.map(&parse_record/1)
    |> parse_element_values
  end

  @spec parse_element_values(list()) :: any()
  defp parse_element_values(elements) do
    if Enum.all?(elements, &is_map/1) do
      Enum.reduce(elements, &Map.merge/2)
    else
      extract_value_from_list(elements)
    end
  end

  @spec extract_value_from_list(list()) :: any()
  defp extract_value_from_list([element]), do: element
  defp extract_value_from_list(elements), do: elements

  def get_fault_tag(xml_response) do
    env_namespace = @soap_version_namespaces[soap_version()] |> String.to_atom

    xml_response
    |> xpath(~x"//namespace::*"l)
    |> Enum.find(fn {_, _, _, _, namespace_url} -> namespace_url == env_namespace end)
    |> construct_fault_tag
  end

  defp construct_fault_tag(nil), do: "Fault"

  defp construct_fault_tag(namespace_element) do
    namespace_element
    |> elem(3)
    |> List.to_string
    |> apply_namespace_to_fault_tag
  end

  defp apply_namespace_to_fault_tag(env_namespace), do: env_namespace <> ":Fault"

  defp soap_version, do: Application.fetch_env!(:soap, :globals)[:version]
end
