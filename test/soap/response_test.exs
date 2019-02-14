defmodule Soap.ResponseTest do
  use ExUnit.Case

  alias Soap.Response
  alias Soap.Response.Parser

  test "#Soap.Response.parse/1 from Soap.Response struct, when request was successful" do
    response = %Response{
      body: Fixtures.load_xml("send_service/SendMessageResponse.xml"),
      headers: [],
      request_url: "",
      status_code: 200
    }

    correctly_parsed_response = %{response: %{message: "Hello!"}}

    assert Response.parse(response) == correctly_parsed_response
  end

  test "#Soap.Response.parse/2, when request was successful" do
    xml_body = Fixtures.load_xml("send_service/SendMessageResponse.xml")
    correctly_parsed_response = %{response: %{message: "Hello!"}}

    assert Response.parse(xml_body, 200) == correctly_parsed_response
  end

  test "#Soap.Response.parse/2, when response contains fault" do
    parsed_fault = %{
      faultcode: "soap:Server",
      faultstring: "System.Web.Services.Protocols.SoapException: Server was unable to process request."
    }

    fault_xml = Fixtures.load_xml("send_service/SendMessageFault.xml")
    assert Parser.parse(fault_xml, :fault) == parsed_fault
  end
end
