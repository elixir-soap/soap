defmodule Soap.ResponseTest do
  use ExUnit.Case

  alias Soap.Response

  test "#parse_body returns a correctly parsed response" do
    xml_body = Fixtures.load_xml("send_service/SendMessageResponse.xml")
    correctly_parsed_response = %{message: "Hello!"}

    assert Response.parse_body(xml_body) == correctly_parsed_response
  end
end
