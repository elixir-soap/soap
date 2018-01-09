defmodule Soap.Request.Options do
  @moduledoc """
  Documentation for Soap.Request.Options.
  """
  import XmlBuilder

  @spec build(soap_action :: String.t() | atom(), params :: map()) :: map()
  def build(soap_action, params) do
    %{
      headers: prepare_headers(soap_action),
      body: prepare_body(soap_action, params)
    }
  end

  @doc """
  Headers generator by soap action.
  """
  @spec prepare_headers(soap_action :: String.t()) :: any()
  defp prepare_headers(soap_action) do
    nil
  end

  @doc """
  Parsing parameters map and generate body xml by given soap action name and body params(Map).
  Returns xml-like string.
  ## Examples

      iex(2)> Soap.Request.Options.build(:get, %{inCommonParms: [{"userID", "WSPB"}]})
      %{body: "<inCommonParms>\n\t<userID>WSPB</userID>\n</inCommonParms>", headers: nil}

  """
  @spec prepare_body(soap_action :: String.t() | atom(), params :: map()) :: String.t()
  defp prepare_body(soap_action, params) do
    params
    |> construct_xml_request_body
    |> Enum.map(&(Tuple.to_list(&1)))
    |> List.foldl([], &(&1 ++ &2))
    |> List.to_tuple
    |> generate
  end

  @doc """
  Convert map to list and recursive handle self values.
  """
  @spec construct_xml_request_body(params :: map()) :: list()
  defp construct_xml_request_body(params) when is_map(params) do
    params |> Map.to_list |> Enum.map(&(construct_xml_request_body(&1)))
  end

  @doc """
  Recursive handle self values.
  """
  @spec construct_xml_request_body(params :: list()) :: list()
  defp construct_xml_request_body(params) when is_list(params) do
    params |> Enum.map(&(construct_xml_request_body(&1)))
  end

  @doc """
  Converting tuple to list, recursive handle self values, adding tag parameters for XmlBuilder and converting back.
  """
  @spec construct_xml_request_body(params :: tuple()) :: tuple()
  defp construct_xml_request_body(params) when is_tuple(params) do
    params
    |> Tuple.to_list
    |> Enum.map(&(construct_xml_request_body(&1)))
    |> insert_tag_parameters
    |> List.to_tuple
  end

  @spec construct_xml_request_body(params :: atom()) :: String.t()
  defp construct_xml_request_body(params) when is_atom(params), do: params |> to_string

  @spec construct_xml_request_body(params :: String.t()) :: String.t()
  defp construct_xml_request_body(params) when is_binary(params), do: params

  @spec construct_xml_request_body(params :: number()) :: String.t()
  defp construct_xml_request_body(params) when is_number(params), do: params |> to_string

  @doc """
  Extract tag parameters from wsdl (e.g. name).
  TO DO!
  """
  @spec tag_parameters(tag_name :: any()) :: any()
  defp tag_parameters(tag_name), do: nil

  @doc """
  Insert tag parameters(e.g. name) into parsed list.
  """
  @spec insert_tag_parameters(params :: list()) :: list()
  defp insert_tag_parameters(params) when is_list(params) do
    tag_name = params |> List.first

    params |> List.insert_at(1, tag_parameters(tag_name))
  end

  @spec insert_tag_parameters(params :: any()) :: any()
  defp insert_tag_parameters(params), do: params
end
