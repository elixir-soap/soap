defmodule Soap.Request.Options do
  defstruct [:headers, :body]
  import XmlBuilder
  @moduledoc """
  Documentation for Soap.Request.Options.
  """

  def init_model(soap_action, params) do
    %Soap.Request.Options{
      headers: prepare_headers(soap_action),
      body: prepare_body(soap_action, params)
    }
  end

  defp prepare_headers(soap_action) do
    nil
  end

  defp prepare_body(soap_action, params) do
    params
    |> construct_xml_request_body
    |> Enum.map(&(Tuple.to_list(&1)))
    |> List.foldl([], &(&1 ++ &2))
    |> List.to_tuple
    |> generate
  end

  defp construct_xml_request_body(params) when is_map(params) do
    params |> Map.to_list |> Enum.map(&(construct_xml_request_body(&1)))
  end

  defp construct_xml_request_body(params) when is_list(params) do
    params |> Enum.map(&(construct_xml_request_body(&1)))
  end

  defp construct_xml_request_body(params) when is_tuple(params) do
    tag_name = params |> Tuple.to_list |> List.first
    params
    |> Tuple.to_list
    |> Enum.map(&(construct_xml_request_body(&1)))
    |> insert_tag_parameters
    |> List.to_tuple
  end

  defp construct_xml_request_body(params) when is_atom(params), do: params |> to_string

  defp construct_xml_request_body(params) when is_binary(params), do: params

  defp construct_xml_request_body(params) when is_number(params), do: params |> to_string

  defp tag_parameters(tag_name), do: nil

  defp insert_tag_parameters(params) when is_list(params) do
    tag_name = params |> List.first

    params |> List.insert_at(1, tag_parameters(tag_name))
  end

  defp insert_tag_parameters(params), do: params
end
