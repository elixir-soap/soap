defmodule Soap.Response do
  import SweetXml

  def parse(xml_response, []) do
    xml_response
    |> xpath(~x"//*/response/*"l)
    |> parse_elements
    |> Enum.reduce(fn x, y -> Map.merge(x, y) end)
  end

  defp parse_record({:xmlElement, tag_name, _, _, _, _, _, _, elements, _, _, _}) do
    %{tag_name => parse_elements(elements)}
  end
  defp parse_record({:xmlText, _, _, _, value, _}) when is_list(value), do: List.to_string(value)
  defp parse_record({:xmlText, _, _, _, value, _}) when is_binary(value), do: value

  defp parse_elements(elements) when is_list(elements) do
    elements
    |> Enum.map(fn x -> parse_record(x) end)
  end
  defp parse_elements(elements) when is_tuple(elements), do: parse_record(elements)
end
