defmodule Soap.ResponseTest do
  use ExUnit.Case

  alias Soap.Response
  alias Soap.Response.Parser

  test "#parse response, when request was successful" do
    xml_body = Fixtures.load_xml("send_service/SendMessageResponse.xml")
    correctly_parsed_response = %{response: %{message: "Hello!"}}

    assert Response.parse(xml_body, 200) == correctly_parsed_response
  end

  test "#parse response, when response contains fault" do
    parsed_fault = %{
      faultcode: "soap:Server",
      faultstring: "System.Web.Services.Protocols.SoapException: Server was unable to process request."
    }

    fault_xml = Fixtures.load_xml("send_service/SendMessageFault.xml")
    assert Parser.parse(fault_xml, :fault) == parsed_fault
  end
end
