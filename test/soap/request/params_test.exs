defmodule Soap.Request.ParamsTest do
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

  test "#build_headers uses the custom WSDL SOAP version" do
    base_headers = [
      {"SOAPAction", "com.esendex.ems.soapinterface/SendMessage12"},
      {"Content-Type", "text/xml;charset=utf-8"}
    ]

    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path, soap_version: "1.2")
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
    parameters = %{recipient: "WSPB", body: "BODY", type: "TYPE", date: "2018-01-19"}
    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path)
    function_result = Params.build_body(wsdl, @operation, parameters)

    assert function_result == xml_body
  end

  test "#build_body uses the custom WSDL SOAP version" do
    xml_body = Fixtures.load_xml("send_service/SendMessageRequest_soap12.xml")
    parameters = %{recipient: "WSPB", body: "BODY", type: "TYPE", date: "2018-01-19"}
    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path, soap_version: "1.2")
    function_result = Params.build_body(wsdl, @operation, parameters)

    assert function_result == xml_body
  end

  test "#build_body converts map to error list" do
    parameters = %{userID: "WSPB", type: "ertert"}
    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path)
    function_result = Params.build_body(wsdl, @operation, parameters)

    assert function_result == [
             "Invalid SOAP message:Invalid content was found starting with element 'userID'. One of {body, date, dateTime, recipient, type} is expected."
           ]
  end

  test "#build_body returns wrong type errors" do
    parameters = %{recipient: 1}
    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path)
    function_result = Params.build_body(wsdl, @operation, parameters)

    assert function_result == [
             "Element recipient has wrong type. Expects string type."
           ]
  end

  test "#build_body returns wrong date format errors" do
    parameters = %{"date" => "09:00:00"}
    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path)
    function_result = Params.build_body(wsdl, @operation, parameters)

    assert function_result == [
             "Element date has wrong format. Expects [0-9]{4}-[0-9]{2}-[0-9]{2} format."
           ]
  end

  test "#get_url returns correct soap:address" do
    endpoint = "http://localhost:8080/soap/SendService"
    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path)
    result = wsdl[:endpoint]

    assert result == endpoint
  end
end
