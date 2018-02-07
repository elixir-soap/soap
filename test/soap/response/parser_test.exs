defmodule Soap.Response.ParserTest do
  use ExUnit.Case
  alias Soap.Response.Parser

  test "correct response parsed successful" do
    xml_body = Fixtures.load_xml("send_service/SendMessageResponse.xml")
    correctly_parsed_response = %{response: %{message: "Hello!"}}

    assert Parser.parse(xml_body, :success) == correctly_parsed_response
  end
end
