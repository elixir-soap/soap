defmodule Soap.Response do
  @moduledoc """
  Documentation for Soap.Request.
  """
  import SweetXml

  @doc """
  Executing with xml response body and list with tag names.
  If a list is empty then parse/2 returns full parsed response structure into map.
  """
  @spec parse(String.t(), list()) :: map()
  def parse(xml_response, []) do
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
  defp parse_elements(elements) when is_list(elements) do
    parsed_elements = Enum.map(elements, &parse_record/1)
    list_with_maps = Enum.all?(elements, &is_map/1)

    handle_elements_list(parsed_elements, list_with_maps)
  end

  defp parse_elements(elements) when is_tuple(elements), do: parse_record(elements)

  @spec handle_elements_list(list(), boolean()) :: map()
  defp handle_elements_list(elements, true), do: Enum.reduce(elements, &Map.merge/2)
  defp handle_elements_list(elements, false), do: extract_value_from_list(elements)

  @spec extract_value_from_list(list()) :: any()
  defp extract_value_from_list(elements) do
    if Enum.count(elements) > 1, do: elements, else: List.first(elements)
  end
end
