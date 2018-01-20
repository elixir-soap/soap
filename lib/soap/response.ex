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
    elements
    |> Enum.map(fn x -> parse_record(x) end)
    |> handle_elements_list
  end
  defp parse_elements(elements) when is_tuple(elements), do: parse_record(elements)

  @spec handle_elements_list(list()) :: map()
  defp handle_elements_list(elements) do
    case Enum.all?(elements, fn x -> is_map(x) end) do
    true ->
      Enum.reduce(elements, fn(x, y) -> Map.merge(x, y) end)
    false ->
      extract_value_from_list(elements)
    end
  end

  @spec extract_value_from_list(list()) :: any()
  defp extract_value_from_list(elements) do
    if Enum.count(elements) > 1, do: elements, else: List.first(elements)
  end
end
