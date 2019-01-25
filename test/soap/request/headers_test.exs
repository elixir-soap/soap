defmodule Soap.Request.HeadersTest do
  use ExUnit.Case
  alias Soap.{Request.Headers, Wsdl}
  doctest Headers
  @wsdl_path Fixtures.get_file_path("wsdl/SendService.wsdl")

  @operation "SendMessage"

  test "#build without custom parameters" do
    base_headers = [
      {"SOAPAction", "com.esendex.ems.soapinterface/SendMessage"},
      {"Content-Type", "text/xml;charset=utf-8"}
    ]

    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path)
    function_result = Headers.build(wsdl, @operation, [])

    assert function_result == base_headers
  end

  test "#build with custom parameters" do
    custom_parameters = [{"SOAPAction", "AnotherAction"}]
    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path)
    function_result = Headers.build(wsdl, @operation, custom_parameters)

    assert function_result == custom_parameters
  end
end
