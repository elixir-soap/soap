defmodule Soap.WsdlTest do
  use ExUnit.Case
  doctest Soap.Wsdl
  alias Soap.Wsdl
  import Mock

  @wsdl Fixtures.load_wsdl("SendService.wsdl")

  @parsed_wsdl %{
    complex_types: [
      %{
        name: "sendMessageMultipleRecipientsResponse",
        type: "tns:sendMessageMultipleRecipientsResponse"
      },
      %{
        name: "sendMessageMultipleRecipients",
        type: "tns:sendMessageMultipleRecipients"
      },
      %{name: "sendMessageResponse", type: "tns:sendMessageResponse"},
      %{name: "sendMessage", type: "tns:sendMessage"}
    ],
    endpoint: "http://localhost:8080/soap/SendService",
    namespaces: %{
      "soap" => %{
        type: :soap,
        value: "http://schemas.xmlsoap.org/wsdl/soap/"
      },
      "soap12" => %{
        type: :soap,
        value: "http://schemas.xmlsoap.org/wsdl/soap12/"
      },
      "tns" => %{type: :wsdl, value: "com.esendex.ems.soapinterface"},
      "wsdl" => %{
        type: :soap,
        value: "http://schemas.xmlsoap.org/wsdl/"
      }
    },
    operations: [
      %{name: "SendMessage", soap_action: "com.esendex.ems.soapinterface/SendMessage"},
      %{
        name: "SendMessageMultipleRecipients",
        soap_action: "com.esendex.ems.soapinterface/SendMessageMultipleRecipients"
      }
    ],
    schema_attributes: %{
      element_form_default: "qualified",
      target_namespace: "com.esendex.ems.soapinterface"
    },
    validation_types: %{
      "recipients" => %{
        "recipient" => %{maxOccurs: "unbounded", minOccurs: "0", type: "xsd:string"}
      },
      "results" => %{
        "result" => %{maxOccurs: "unbounded", minOccurs: "0", type: "xsd:string"}
      },
      "sendmessage" => %{
        "body" => %{minOccurs: "0", type: "xsd:string"},
        "recipient" => %{minOccurs: "0", type: "xsd:string"},
        "type" => %{type: "xsd:string"},
        "date" => %{type: "xsd:date"},
        "dateTime" => %{type: "xsd:dateTime"}
      },
      "sendmessagemultiplerecipients" => %{
        "body" => %{minOccurs: "0", type: "xsd:string"},
        "recipients" => %{minOccurs: "0", type: "tns:recipients"},
        "type" => %{type: "xsd:string"},
        "dateTimes" => %{minOccurs: "0", type: "tns:dateTimes"},
        "dates" => %{minOccurs: "0", type: "tns:dates"}
      },
      "sendmessagemultiplerecipientsresponse" => %{
        "results" => %{minOccurs: "0", type: "tns:results"}
      },
      "sendmessageresponse" => %{
        "sendMessageResult" => %{minOccurs: "0", type: "xsd:string"}
      },
      "dates" => %{
        "date" => %{maxOccurs: "unbounded", minOccurs: "0", type: "xsd:date"}
      },
      "datetimes" => %{
        "dateTime" => %{maxOccurs: "unbounded", minOccurs: "0", type: "xsd:dateTime"}
      }
    }
  }

  @parsed_root_namespace_wsdl %{
    complex_types: [
      %{name: "TradePriceRequest", type: ""},
      %{name: "TradePrice", type: ""}
    ],
    endpoint: "http://example.com/stockquote",
    namespaces: %{
      "" => %{type: :soap, value: "http://schemas.xmlsoap.org/wsdl/"},
      "soap" => %{type: :soap, value: "http://schemas.xmlsoap.org/wsdl/soap/"},
      "tns" => %{type: :wsdl, value: "http://example.com/stockquote.wsdl"},
      "xsd1" => %{type: :soap, value: "http://example.com/stockquote.xsd"}
    },
    operations: [
      %{
        name: "GetLastTradePrice",
        soap_action: "http://example.com/GetLastTradePrice"
      }
    ],
    schema_attributes: %{
      element_form_default: "",
      target_namespace: "http://example.com/stockquote.xsd"
    },
    validation_types: %{}
  }

  test "#parse_from_file returns {:ok, wsdl}" do
    wsdl_path = Fixtures.get_file_path("wsdl/SendService.wsdl")
    assert(Wsdl.parse_from_file(wsdl_path) == {:ok, @parsed_wsdl})
  end

  test "#parse_from_url returns {:ok, wsdl}" do
    with_mock HTTPoison, get!: fn _, _, _ -> %HTTPoison.Response{body: @wsdl} end do
      assert Wsdl.parse_from_url("any_url") == {:ok, @parsed_wsdl}
    end
  end

  test "#parse returns {:ok, wsdl}" do
    assert Wsdl.parse(@wsdl, "SendService.wsdl") == {:ok, @parsed_wsdl}
  end

  test "#get_namespaces returns correctly namespaces list" do
    schema_namespace = Wsdl.get_schema_namespace(@wsdl)

    namespaces_list = %{
      "soap" => %{type: :soap, value: "http://schemas.xmlsoap.org/wsdl/soap/"},
      "soap12" => %{type: :soap, value: "http://schemas.xmlsoap.org/wsdl/soap12/"},
      "tns" => %{type: :wsdl, value: "com.esendex.ems.soapinterface"},
      "wsdl" => %{type: :soap, value: "http://schemas.xmlsoap.org/wsdl/"}
    }

    assert Wsdl.get_namespaces(@wsdl, schema_namespace, "wsdl") == namespaces_list
  end

  test "#get_endpoint returns correctly endpoint" do
    assert Wsdl.get_endpoint(@wsdl, "wsdl") == "http://localhost:8080/soap/SendService"
  end

  test "#get_complex_types returns list of types" do
    schema_namespace = Wsdl.get_schema_namespace(@wsdl)

    types = [
      %{name: "sendMessageMultipleRecipientsResponse", type: "tns:sendMessageMultipleRecipientsResponse"},
      %{name: "sendMessageMultipleRecipients", type: "tns:sendMessageMultipleRecipients"},
      %{name: "sendMessageResponse", type: "tns:sendMessageResponse"},
      %{name: "sendMessage", type: "tns:sendMessage"}
    ]

    assert Wsdl.get_complex_types(@wsdl, schema_namespace, "wsdl") == types
  end

  test "#get_validation_types returns validation struct" do
    assert Wsdl.get_validation_types(@wsdl, "SendService.wsdl", "wsdl") == @parsed_wsdl.validation_types
  end

  test "support for root namespaces" do
    wsdl_path = Fixtures.get_file_path("wsdl/RootNamespace.wsdl")
    assert(Wsdl.parse_from_file(wsdl_path) == {:ok, @parsed_root_namespace_wsdl})
  end
end
