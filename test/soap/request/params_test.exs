defmodule Soap.Request.ParamsTest do
  use ExUnit.Case
  doctest Soap.Request.Params
  alias Soap.{Request.Params, Wsdl}
  @wsdl_path Fixtures.get_file_path("wsdl/SendService.wsdl")

  @operation "SendMessage"

  test "#build_body converts map to Xml-like string successful" do
    xml_body = Fixtures.load_xml("send_service/SendMessageRequest.xml")
    parameters = %{recipient: "WSPB", body: "BODY", type: "TYPE", date: "2018-01-19"}
    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path)
    function_result = Params.build_body(wsdl, @operation, parameters, nil)

    assert function_result == xml_body
  end

  test "#build_body uses the custom WSDL SOAP version" do
    xml_body = Fixtures.load_xml("send_service/SendMessageRequest_soap12.xml")
    parameters = %{recipient: "WSPB", body: "BODY", type: "TYPE", date: "2018-01-19"}
    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path, soap_version: "1.2")
    function_result = Params.build_body(wsdl, @operation, parameters, nil)

    assert function_result == xml_body
  end

  test "#build_body converts map to error list" do
    parameters = %{userID: "WSPB", type: "ertert"}
    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path)
    function_result = Params.build_body(wsdl, @operation, parameters, nil)

    assert function_result == [
             "Invalid SOAP message:Invalid content was found starting with element 'userID'. One of {body, date, dateTime, recipient, type} is expected."
           ]
  end

  test "#build_body returns wrong type errors" do
    parameters = %{recipient: 1}
    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path)
    function_result = Params.build_body(wsdl, @operation, parameters, nil)

    assert function_result == [
             "Element recipient has wrong type. Expects string type."
           ]
  end

  test "string type params can be all digits" do
    xml_body =
      Fixtures.load_xml("send_service/SendMessageRequest.xml")
      |> String.replace("WSPB", "123")

    parameters = %{recipient: "123", body: "BODY", type: "TYPE", date: "2018-01-19"}
    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path)
    function_result = Params.build_body(wsdl, @operation, parameters, nil)

    assert function_result == xml_body
  end

  test "values can be marked as safe" do
    xml_body =
      Fixtures.load_xml("send_service/MarkedAsSafeRequest.xml")
      |> String.replace("WSPB", "123")

    parameters = %{type: {:__safe, "TY&PE"}}
    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path)
    # This will be an invalid XML file, but we need to test that XmlBuilder
    # sends the value straight through
    function_result = Params.build_body(wsdl, @operation, parameters, nil)

    assert function_result == xml_body
  end

  test "#build_body returns wrong date format errors" do
    parameters = %{"date" => "09:00:00"}
    {_, wsdl} = Wsdl.parse_from_file(@wsdl_path)
    function_result = Params.build_body(wsdl, @operation, parameters, nil)

    assert function_result == [
             "Element date has wrong format. Expects [0-9]{4}-[0-9]{2}-[0-9]{2} format."
           ]
  end

  test "#build_body without complex types" do
    xml_body = Fixtures.load_xml("cyber_source_transaction/runTransactionRequest.xml")
    {_, wsdl} = Wsdl.parse_from_file(Fixtures.get_file_path("wsdl/CyberSourceTransaction.wsdl"))
    function_result = Params.build_body(wsdl, "runTransaction", %{}, nil)

    assert function_result == xml_body
  end

  test "using tuple params to set xml attributes" do
    xml_body =
      "runTransaction-template.xml"
      |> Fixtures.load_xml()
      |> String.replace("{{BODY}}", ~s{<test foo="bar"/>})

    {_, wsdl} = Wsdl.parse_from_file(Fixtures.get_file_path("wsdl/CyberSourceTransaction.wsdl"))
    function_result = Params.build_body(wsdl, "runTransaction", {:test, %{foo: "bar"}, []}, nil)

    assert function_result == xml_body
  end

  test "using tuple params to set xml attributes (nested)" do
    xml_body =
      "runTransaction-template.xml"
      |> Fixtures.load_xml()
      |> String.replace(
        "{{BODY}}",
        ~s{<test><Person id="something"><firstName>Joe</firstName><lastName>Dirt</lastName></Person></test>}
      )

    {_, wsdl} = Wsdl.parse_from_file(Fixtures.get_file_path("wsdl/CyberSourceTransaction.wsdl"))

    function_result =
      Params.build_body(
        wsdl,
        "runTransaction",
        %{test: {:Person, %{id: "something"}, %{firstName: "Joe", lastName: "Dirt"}}},
        nil
      )

    assert function_result == xml_body
  end

  test "using tuple params to set xml attributes (list)" do
    xml_body =
      "runTransaction-template.xml"
      |> Fixtures.load_xml()
      |> String.replace("{{BODY}}", ~s{<one num="1"/><two num="2"/>})

    {_, wsdl} = Wsdl.parse_from_file(Fixtures.get_file_path("wsdl/CyberSourceTransaction.wsdl"))
    function_result = Params.build_body(wsdl, "runTransaction", [{:one, %{num: 1}, []}, {:two, %{num: 2}, []}], nil)

    assert function_result == xml_body
  end
end
