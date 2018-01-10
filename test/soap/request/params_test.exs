defmodule Soap.Request.ParamsTest do
  use ExUnit.Case
  doctest Soap.Request.Params
  alias Soap.Request.Params

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

  test "#get_url extract url from wsdl successful" do
    wsdl = %{endpoint: "test_endpoint.com"}
    function_result = Params.get_url wsdl

    assert function_result == wsdl[:endpoint]
  end
end
