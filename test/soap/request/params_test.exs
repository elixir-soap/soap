defmodule Soap.Request.ParamsTest do
  use ExUnit.Case
  # doctest Soap.Request.Params
  alias Soap.Request.Params
  alias Soap.Wsdl

  @soap_action :testAction

  test "#build_headers without custom parameters" do
    base_headers    = [{"SOAPAction", "testAction"}, {"Content-Type", "text/xml;charset=UTF-8"}]
    function_result = Params.build_headers @soap_action, []

    assert function_result == base_headers
  end

  test "#build_headers with custom parameters" do
    custom_parameters = [{"SOAPAction", "AnotherAction"}]
    function_result   = Params.build_headers @soap_action, custom_parameters

    assert function_result == custom_parameters
  end

  test "#build_body converts map to Xml-like string successful" do
    xml_body   = "<inCommonParms>\n\t<userID>WSPB</userID>\n</inCommonParms>"
    parameters = %{inCommonParms: [{"userID", "WSPB"}]}
    function_result = Params.build_body @soap_action, parameters

    assert function_result == xml_body
  end

  test "#get_url returns correct soap:address" do
    endpoint  = "http://localhost:8080/soap/SendService"
    wsdl_path = Path.expand("../fixtures/SendService.wsdl", __DIR__)
    {_, wsdl} = Wsdl.parse_from_file(wsdl_path)
    result    = wsdl |> Wsdl.get_endpoint |> to_string

    assert result == endpoint
  end
end
