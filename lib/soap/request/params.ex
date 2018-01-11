defmodule Soap.Request.Params do
  @moduledoc """
  Documentation for Soap.Request.Options.
  """
  import XmlBuilder, only: [generate: 1]
  alias Soap.Wsdl

  @doc """
  Headers generator by soap action and custom headers.
  ## Examples

  """
  @spec build_headers(soap_action :: String.t(), custom_headers :: list()) :: list()
  def build_headers(soap_action, custom_headers) do
    extract_headers(soap_action, custom_headers)
  end

  @doc """
  Returns endpoint url from wsdl.
  """
  @spec get_url(wsdl :: map()) :: String.t()
  def get_url(wsdl) do
    Wsdl.get_endpoint(wsdl)
  end

  @doc """
  Parsing parameters map and generate body xml by given soap action name and body params(Map).
  Returns xml-like string.
  ## Examples

      iex(2)> Soap.Request.Params.build_body("wsdl", :get, %{inCommonParms: [{"userID", "WSPB"}]})
      "<inCommonParms>\n\t<userID>WSPD</userID>\n</inCommonParms>"

  """
  @spec build_body(wsdl :: String.t(), soap_action :: String.t() | atom(), params :: map()) :: String.t()
  def build_body(wsdl, soap_action, params) do
    params
    |> build_action_tag(wsdl, soap_action)
    |> construct_xml_request_body
    |> Enum.map(&Tuple.to_list/1)
    |> List.foldl([], &(&1 ++ &2))
    |> List.to_tuple
    |> generate
  end

  defp base_headers(soap_action) do
    [{"SOAPAction", to_string(soap_action)},
     {"Content-Type", "text/xml;charset=UTF-8"}]
  end

  defp extract_headers(soap_action, []), do: base_headers(soap_action)

  defp extract_headers(_, custom_headers), do: custom_headers

  @spec construct_xml_request_body(params :: map() | list()) :: list()
  defp construct_xml_request_body(params) when is_map(params) or is_list(params) do
    params |> Enum.map(&construct_xml_request_body/1)
  end

  @spec construct_xml_request_body(params :: tuple()) :: tuple()
  defp construct_xml_request_body(params) when is_tuple(params) do
    params
    |> Tuple.to_list
    |> Enum.map(&construct_xml_request_body/1)
    |> insert_tag_parameters
    |> List.to_tuple
  end

  @spec construct_xml_request_body(params :: atom() | number()) :: String.t()
  defp construct_xml_request_body(params) when is_atom(params) or is_number(params), do: params |> to_string

  @spec construct_xml_request_body(params :: String.t()) :: String.t()
  defp construct_xml_request_body(params) when is_binary(params), do: params

  @spec tag_parameters(tag_name :: any()) :: any()
  defp tag_parameters(tag_name), do: nil

  @spec insert_tag_parameters(params :: list()) :: list()
  defp insert_tag_parameters(params) when is_list(params) do
    tag_name = params |> List.first

    params |> List.insert_at(1, tag_parameters(tag_name))
  end

  @spec insert_tag_parameters(params :: any()) :: any()
  defp insert_tag_parameters(params), do: params

  defp build_action_tag(params, wsdl, soap_action) do
    wsdl
    |> Wsdl.get_complex_types
    |> Enum.find(fn(x) -> x[:name] == soap_action end)
    |> Map.get(:type)
    |> add_parrent_element(params)
  end

  defp add_parrent_element(element, params) do
    %{
      element => params
    }
  end
end
