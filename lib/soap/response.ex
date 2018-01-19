defmodule Soap.Response do
  import SweetXml

  def parse(xml_response, []) do
    xml_response
    |> xpath(~x"//response/*"l)
    |> parse_elements
  end

  defp parse_record({:xmlElement, tag_name, _, _, _, _, _, _, elements, _, _, _}) do
    %{tag_name => parse_elements(elements)}
  end
  defp parse_record({:xmlText, _, _, _, value, _}) when is_list(value), do: List.to_string(value)
  defp parse_record({:xmlText, _, _, _, value, _}) when is_binary(value), do: value

  defp parse_elements(elements) when is_list(elements) do
    elements
    |> Enum.map(fn x -> parse_record(x) end)
    |> handle_elements_list
  end
  defp parse_elements(elements) when is_tuple(elements), do: parse_record(elements)

  defp handle_elements_list(elements) do
    case Enum.all?(elements, fn x -> is_map(x) end) do
    true ->
      Enum.reduce(elements, fn(x, y) -> Map.merge(x, y) end)
    false ->
      extract_value_from_list(elements)
    end
  end

  defp extract_value_from_list(elements) do
    if Enum.count(elements) > 1, do: elements, else: List.first(elements)
  end
end
