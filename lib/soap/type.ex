defmodule Soap.Type do
  @moduledoc """
  Provides functions for parsing types to struct
  """

  import SweetXml, except: [parse: 1]

  @spec get_complex_types(String.t(), String.t()) :: list()
  def get_complex_types(wsdl, x_path) do
    wsdl
    |> xpath(~x"#{x_path}"l)
    |> Enum.reduce(%{}, &parse_types/2)
  end

  @spec parse_types(map(), map()) :: map()
  defp parse_types(type_node, complex_type_acc) do
    types_map =
      type_node
      |> xpath(~x"./xsd:sequence/xsd:element"l)
      |> Enum.reduce(%{}, &parse_type_attributes/2)

    Map.put(complex_type_acc, type_node |> xpath(~x"./@name"s) |> String.downcase(), types_map)
  end

  @spec parse_type_attributes(map(), map()) :: map()
  defp parse_type_attributes(inner_node, element_acc) do
    result_map =
      [:nillable, :minOccurs, :maxOccurs]
      |> Enum.reduce(%{type: inner_node |> xpath(~x"./@type"s)}, fn attr, init_map_acc ->
        attr_val = inner_node |> xpath(~x"./@#{attr}"s)

        case attr_val do
          "" -> init_map_acc
          _ -> Map.put(init_map_acc, attr, attr_val)
        end
      end)

    Map.put(element_acc, inner_node |> xpath(~x"./@name"s), result_map)
  end
end
