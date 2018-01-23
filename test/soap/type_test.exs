defmodule Soap.TypeTest do
  use ExUnit.Case
  doctest Soap.Type
  alias Soap.Type

  @complex_types %{
    "dates" => %{
      "date" => %{maxOccurs: "unbounded", minOccurs: "0", type: "xsd:date"}
    },
    "datetimes" => %{
      "dateTime" => %{
        maxOccurs: "unbounded",
        minOccurs: "0",
        type: "xsd:dateTime"
      }
    },
    "recipients" => %{
      "recipient" => %{maxOccurs: "unbounded", minOccurs: "0", type: "xsd:string"}
    },
    "results" => %{
      "result" => %{maxOccurs: "unbounded", minOccurs: "0", type: "xsd:string"}
    },
    "sendmessage" => %{
      "body" => %{minOccurs: "0", type: "xsd:string"},
      "date" => %{type: "xsd:date"},
      "dateTime" => %{type: "xsd:dateTime"},
      "recipient" => %{minOccurs: "0", type: "xsd:string"},
      "type" => %{type: "xsd:string"}
    },
    "sendmessagemultiplerecipients" => %{
      "body" => %{minOccurs: "0", type: "xsd:string"},
      "dateTimes" => %{minOccurs: "0", type: "tns:dateTimes"},
      "dates" => %{minOccurs: "0", type: "tns:dates"},
      "recipients" => %{minOccurs: "0", type: "tns:recipients"},
      "type" => %{type: "xsd:string"}
    },
    "sendmessagemultiplerecipientsresponse" => %{
      "results" => %{minOccurs: "0", type: "tns:results"}
    },
    "sendmessageresponse" => %{
      "sendMessageResult" => %{minOccurs: "0", type: "xsd:string"}
    }
  }

  test "#get_complex_types returns map with complex types" do
    wsdl_path = Fixtures.get_file_path("wsdl/SendService.wsdl")
    {:ok, wsdl} = File.read(wsdl_path)
    assert(Type.get_complex_types(wsdl, "//wsdl:types/xsd:schema/xsd:complexType") == @complex_types)
  end
end
