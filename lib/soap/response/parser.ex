defmodule Soap.Response.Parser do
  @moduledoc """
  Provides a functions for parse an xml-like response body.
  """

  import SweetXml, only: [xpath: 2, sigil_x: 2]

  @doc """
  Executing with xml response body.
  If a list is empty then parse/1 returns full parsed response structure into map.
  """
  @spec parse(String.t()) :: map()

  def parse(xml_response) do
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
    if Enum.all?(elements, &is_map/1), do: Enum.reduce(elements, &Map.merge/2), else: extract_value_from_list(elements)
  end

  @spec extract_value_from_list(list()) :: any()
  defp extract_value_from_list(elements) do
    if Enum.count(elements) > 1, do: elements, else: List.first(elements)
  end
end
