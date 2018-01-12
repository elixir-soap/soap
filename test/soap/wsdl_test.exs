defmodule Soap.WsdlTest do
  use ExUnit.Case
  doctest Soap.Wsdl
  alias Soap.Wsdl
  import Mock

  @wsdl Fixtures.load_wsdl("SendService.wsdl")

  test "#parse_from_file returns {:ok, wsdl}" do
    wsdl_path = Fixtures.get_file_path("wsdl/SendService.wsdl")
    assert(Wsdl.parse_from_file(wsdl_path) == {:ok, @wsdl})
  end

  test "#parse_from_url returns {:ok, wsdl}" do
    with_mock(HTTPoison, [get!: fn(_) -> %HTTPoison.Response{body: @wsdl} end]) do
      assert Wsdl.parse_from_url("any_url") == {:ok, @wsdl}
    end
  end

  test "#parse returns {:ok, wsdl}" do
    assert Wsdl.parse(@wsdl) == {:ok, @wsdl}
  end

  test "#get_namespaces returns correctly namespaces list" do
    namespaces_list = %{
      "soap" => %{type: :soap, value: "http://schemas.xmlsoap.org/wsdl/soap/"},
      "soap12" => %{type: :soap, value: "http://schemas.xmlsoap.org/wsdl/soap12/"},
      "tns" => %{type: :wsdl, value: "com.esendex.ems.soapinterface"},
      "wsdl" => %{type: :soap, value: "http://schemas.xmlsoap.org/wsdl/"}
    }

    assert Wsdl.get_namespaces(@wsdl) == namespaces_list
  end

  test "#get_endpoint returns correctly endpoint" do
    assert Wsdl.get_endpoint(@wsdl) == "http://localhost:8080/soap/SendService"
  end

  test "#get_complex_types returns list of types" do
    types = [
      %{name: "sendMessageMultipleRecipientsResponse", type: "tns:sendMessageMultipleRecipientsResponse"},
      %{name: "sendMessageMultipleRecipients", type: "tns:sendMessageMultipleRecipients"},
      %{name: "sendMessageResponse", type: "tns:sendMessageResponse"},
      %{name: "sendMessage", type: "tns:sendMessage"}
    ]

    assert Wsdl.get_complex_types(@wsdl) == types
  end
end
