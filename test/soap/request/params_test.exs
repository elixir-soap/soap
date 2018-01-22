defmodule Soap.Request.ParamsTest do
  @moduledoc false

  use ExUnit.Case
  doctest Soap.Request.Params
  alias Soap.{Request.Params, Wsdl}
  @wsdl_path Fixtures.get_file_path("wsdl/SendService.wsdl")

  @operation "SendMessage"

  test "#build_headers without custom parameters" do
    base_headers = [
      {"SOAPAction", "com.esendex.ems.soapinterface/SendMessage"},
      {"Content-Type", "text/xml;charset=utf-8"}
    ]

    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path)
    function_result = Params.build_headers(wsdl, @operation, [])

    assert function_result == base_headers
  end

  test "#build_headers with custom parameters" do
    custom_parameters = [{"SOAPAction", "AnotherAction"}]
    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path)
    function_result = Params.build_headers(wsdl, @operation, custom_parameters)

    assert function_result == custom_parameters
  end

  test "#build_body converts map to Xml-like string successful" do
    xml_body = Fixtures.load_xml("send_service/SendMessageRequest.xml")
    parameters = %{inCommonParms: [{"userID", "WSPB"}]}
    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path)
    function_result = Params.build_body(wsdl, @operation, parameters)

    assert function_result == xml_body
  end

  test "#get_url returns correct soap:address" do
    endpoint = "http://localhost:8080/soap/SendService"
    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path)
    result = wsdl[:endpoint]

    assert result == endpoint
  end
end
