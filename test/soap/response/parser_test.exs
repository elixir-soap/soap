defmodule Soap.Response.ParserTest do
  use ExUnit.Case
  alias Soap.Response.Parser

  test "correct response parsed successful" do
    xml_body = Fixtures.load_xml("send_service/SendMessageResponse.xml")
    correctly_parsed_response = %{message: "Hello!"}

    assert Parser.parse(xml_body) == correctly_parsed_response
  end

  test "when response is empty" do
    assert Parser.parse("") == %{}
  end

  test "when response not include response-tag" do
    fault_xml = Fixtures.load_xml("send_service/SendMessageFault.xml")
    assert Parser.parse(fault_xml) == %{}
  end
end
