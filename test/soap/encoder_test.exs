defmodule Soap.EncoderTest do
  use ExUnit.Case, async: true

  import Soap.Conformance.Support, only: [wsdl: 1]

  alias Soap.{Attachment, Encoder, Error, Raw, Service}
  alias Soap.Conformance.Xml

  @xsi "http://www.w3.org/2001/XMLSchema-instance"
  @soap12 "http://schemas.xmlsoap.org/wsdl/soap12/"

  defp encode(fields, params, opts \\ [], wsdl_opts \\ []) do
    {:ok, service} = Service.from_string(wsdl([fields: fields] ++ wsdl_opts))
    {:ok, operation} = Service.operation(service, "Pay")
    Encoder.encode(service, operation, params, opts)
  end

  defp body(fields, params, opts \\ [], wsdl_opts \\ []) do
    {:ok, %{xml: xml}} = encode(fields, params, opts, wsdl_opts)
    {:ok, doc} = Xml.parse(xml)
    {:ok, [wrapper]} = Xml.body_children(doc)
    wrapper
  end

  defp field(name, type, extra \\ ""), do: ~s(<xsd:element name="#{name}" type="#{type}"#{extra}/>)

  defp texts(wrapper), do: Enum.map(wrapper.children, &{&1.name, &1.text})

  describe "params" do
    @fields ~s(<xsd:element name="a" type="xsd:string"/><xsd:element name="b" type="xsd:string"/>)

    test "takes maps, keyword lists and tuples, with atom or string names" do
      for params <- [
            %{a: "1", b: "2"},
            %{"a" => "1", "b" => "2"},
            [a: "1", b: "2"],
            [{"a", "1"}, {"b", "2"}],
            [{"a", %{}, "1"}, {:b, %{}, "2"}]
          ] do
        assert texts(body(@fields, params)) == [{"a", "1"}, {"b", "2"}]
      end
    end

    test "ignores a prefix on a name" do
      assert texts(body(@fields, %{"p:a" => "1"})) == [{"a", "1"}]
    end

    test "orders fields by the schema" do
      assert texts(body(@fields, b: "2", a: "1")) == [{"a", "1"}, {"b", "2"}]
    end

    test "a list repeats the element" do
      fields = field("a", "xsd:string", ~s( maxOccurs="unbounded"))
      assert texts(body(fields, %{a: ["1", "2"]})) == [{"a", "1"}, {"a", "2"}]
    end

    test "nested maps follow nested types" do
      extra =
        ~s(<xsd:complexType name="N"><xsd:sequence><xsd:element name="x" type="xsd:int"/><xsd:element name="y" type="xsd:int"/></xsd:sequence></xsd:complexType>)

      wrapper = body(field("n", "tns:N"), %{n: %{y: 2, x: 1}}, [], extra_types: extra)

      assert [%{name: "n", children: [%{name: "x", text: "1", ns: "urn:t"}, %{name: "y", text: "2"}]}] =
               wrapper.children
    end

    test "unknown elements are errors, and validate: false sends them" do
      assert {:error, %Error{reason: {:invalid_param, "Pay/c", message}}} = encode(@fields, %{c: "1"})
      assert message =~ "a, b"
      assert texts(body(@fields, %{c: "1"}, validate: false)) == [{"c", "1"}]
    end

    test "a bad entry is an error" do
      assert {:error, %Error{reason: {:invalid_param, _, _}}} = encode(@fields, ["nope"])
    end

    test "a scalar where elements belong is an error" do
      extra =
        ~s(<xsd:complexType name="N"><xsd:sequence><xsd:element name="x" type="xsd:int"/></xsd:sequence></xsd:complexType>)

      assert {:error, %Error{reason: {:invalid_param, "Pay/n", _}}} =
               encode(field("n", "tns:N"), %{n: "text"}, [], extra_types: extra)
    end

    test "missing required elements are allowed" do
      assert texts(body(@fields, %{})) == []
    end
  end

  describe "attributes and text" do
    test "takes @ keys and #text" do
      wrapper = body(field("a", "xsd:string"), %{a: %{"@lang" => "en", "#text" => "hi"}})
      assert [%{text: "hi", attrs: %{{nil, "lang"} => "en"}}] = wrapper.children
    end

    test "takes a tuple's attributes" do
      wrapper = body(field("a", "xsd:string"), [{"a", %{"lang" => "en"}, "hi"}])
      assert [%{text: "hi", attrs: %{{nil, "lang"} => "en"}}] = wrapper.children
    end

    test "formats declared attributes by their type" do
      extra =
        ~s(<xsd:complexType name="N"><xsd:sequence/><xsd:attribute name="on" type="xsd:boolean"/></xsd:complexType>)

      wrapper = body(field("n", "tns:N"), %{n: %{"@on" => true}}, [], extra_types: extra)
      assert [%{attrs: %{{nil, "on"} => "true"}}] = wrapper.children
    end

    test "simple content takes text and attributes" do
      extra =
        ~s(<xsd:complexType name="P"><xsd:simpleContent><xsd:extension base="xsd:decimal"><xsd:attribute name="cur" type="xsd:string"/></xsd:extension></xsd:simpleContent></xsd:complexType>)

      wrapper = body(field("p", "tns:P"), %{p: %{"@cur" => "EUR", "#text" => 10}}, [], extra_types: extra)
      assert [%{text: "10", attrs: %{{nil, "cur"} => "EUR"}}] = wrapper.children
    end
  end

  describe "nil" do
    test "a nillable element is sent as xsi:nil" do
      wrapper = body(field("a", "xsd:string", ~s( nillable="true")), %{a: nil})
      assert [%{attrs: %{{@xsi, "nil"} => "true"}, text: ""}] = wrapper.children
    end

    test "any other element is left out" do
      assert body(field("a", "xsd:string"), %{a: nil}).children == []
    end
  end

  describe "values" do
    test "formats values by type" do
      cases = [
        {"xsd:int", 5, "5"},
        {"xsd:long", "5", "5"},
        {"xsd:decimal", 1.5, "1.5"},
        {"xsd:decimal", Decimal.new("10.50"), "10.50"},
        {"xsd:decimal", Decimal.new("1E+3"), "1000"},
        {"xsd:double", 1.5, "1.5"},
        {"xsd:double", "INF", "INF"},
        {"xsd:boolean", true, "true"},
        {"xsd:boolean", "0", "false"},
        {"xsd:date", ~D[2024-01-02], "2024-01-02"},
        {"xsd:date", "2024-01-02Z", "2024-01-02Z"},
        {"xsd:dateTime", ~U[2024-01-02 03:04:05Z], "2024-01-02T03:04:05Z"},
        {"xsd:dateTime", ~N[2024-01-02 03:04:05], "2024-01-02T03:04:05"},
        {"xsd:dateTime", "2024-01-02T03:04:05+01:00", "2024-01-02T03:04:05+01:00"},
        {"xsd:time", ~T[03:04:05], "03:04:05"},
        {"xsd:base64Binary", <<1, 2, 255>>, "AQL/"},
        {"xsd:hexBinary", <<1, 255>>, "01FF"},
        {"xsd:string", 5, "5"},
        {"xsd:anyURI", "urn:x", "urn:x"}
      ]

      for {type, value, text} <- cases do
        assert [%{text: ^text}] = body(field("a", type), %{a: value}).children, "#{type} with #{inspect(value)}"
      end
    end

    test "rejects values that can't fit the type" do
      cases = [
        {"xsd:int", "x"},
        {"xsd:int", "1.5"},
        {"xsd:decimal", "abc"},
        {"xsd:double", "abc"},
        {"xsd:boolean", "maybe"},
        {"xsd:date", "xx2024-01-01yy"},
        {"xsd:date", "2024-99-99"},
        {"xsd:dateTime", "garbage"},
        {"xsd:dateTime", "2024-01-01"},
        {"xsd:time", "25:00"},
        {"xsd:base64Binary", 5}
      ]

      for {type, value} <- cases do
        assert {:error, %Error{reason: {:invalid_param, "Pay/a", _}}} = encode(field("a", type), %{a: value}),
               "#{type} with #{inspect(value)}"
      end
    end

    test "validate: false sends them anyway" do
      assert [%{text: "x"}] = body(field("a", "xsd:int"), %{a: "x"}, validate: false).children
    end

    test "checks enumerations, including inherited ones" do
      extra =
        ~s(<xsd:simpleType name="C"><xsd:restriction base="xsd:string"><xsd:enumeration value="red"/></xsd:restriction></xsd:simpleType><xsd:simpleType name="D"><xsd:restriction base="tns:C"/></xsd:simpleType>)

      assert [%{text: "red"}] = body(field("a", "tns:D"), %{a: "red"}, [], extra_types: extra).children

      assert {:error, %Error{reason: {:invalid_param, _, message}}} =
               encode(field("a", "tns:D"), %{a: "blue"}, [], extra_types: extra)

      assert message =~ "red"
    end

    test "a list type joins its values" do
      extra = ~s(<xsd:simpleType name="L"><xsd:list itemType="xsd:int"/></xsd:simpleType>)
      assert [%{text: "1 2"}] = body(field("a", "tns:L"), %{a: [1, 2]}, [], extra_types: extra).children
    end

    test "escapes text and attributes, and keeps whitespace" do
      wrapper = body(field("a", "xsd:string"), [{"a", %{"t" => ~s(<"&\n)}, "a<b&c>\n\t \r"}])
      assert [%{text: "a<b&c>\n\t \r", attrs: %{{nil, "t"} => ~s(<"&\n)}}] = wrapper.children
    end

    test "a value that is one CDATA section stays one" do
      {:ok, %{xml: xml}} = encode(field("a", "xsd:string"), %{a: "<![CDATA[a<b]]>"})
      assert xml =~ "<![CDATA[a<b]]>"
    end

    test "CDATA can't be used to break out" do
      {:ok, %{xml: xml}} = encode(field("a", "xsd:string"), %{a: "<![CDATA[x]]><evil/><![CDATA[y]]>"})
      refute xml =~ "<evil/>"
    end
  end

  describe "raw XML" do
    test "goes out as is, in a field or as a whole element's content" do
      {:ok, %{xml: xml}} = encode(field("a", "xsd:string"), %{a: %Raw{xml: "<x>1</x>"}})
      assert xml =~ "<x>1</x>"
    end

    test "works as a SOAP header" do
      {:ok, %{xml: xml}} = encode(field("a", "xsd:string"), %{}, headers: [%Raw{xml: "<h/>"}])
      assert xml =~ "<h/>"
    end
  end

  describe "types" do
    test "includes base type fields, base first" do
      extra =
        ~s(<xsd:complexType name="B"><xsd:sequence><xsd:element name="b" type="xsd:string"/></xsd:sequence></xsd:complexType><xsd:complexType name="C"><xsd:complexContent><xsd:extension base="tns:B"><xsd:sequence><xsd:element name="c" type="xsd:string"/></xsd:sequence></xsd:extension></xsd:complexContent></xsd:complexType>)

      wrapper = body(field("n", "tns:C"), %{n: %{c: "2", b: "1"}}, [], extra_types: extra)
      assert [%{children: [%{name: "b"}, %{name: "c"}]}] = wrapper.children
    end

    test "a repeating choice keeps the caller's order" do
      fields =
        ~s(<xsd:choice maxOccurs="unbounded"><xsd:element name="a" type="xsd:string"/><xsd:element name="b" type="xsd:string"/></xsd:choice>)

      wrapper =
        body(field("n", "tns:N"), %{n: [b: "1", a: "2", b: "3"]}, [],
          extra_types: ~s(<xsd:complexType name="N">#{fields}</xsd:complexType>)
        )

      assert [%{children: [%{name: "b"}, %{name: "a"}, %{name: "b"}]}] = wrapper.children
    end

    test "xsd:any allows anything" do
      extra =
        ~s(<xsd:complexType name="N"><xsd:sequence><xsd:any maxOccurs="unbounded"/></xsd:sequence></xsd:complexType>)

      wrapper = body(field("n", "tns:N"), %{n: %{free: "1"}}, [], extra_types: extra)
      assert [%{children: [%{name: "free", text: "1"}]}] = wrapper.children
    end

    test "groups and element references resolve" do
      extra =
        ~s(<xsd:element name="R" type="xsd:int"/><xsd:group name="G"><xsd:sequence><xsd:element name="g" type="xsd:int"/></xsd:sequence></xsd:group><xsd:complexType name="N"><xsd:sequence><xsd:group ref="tns:G"/><xsd:element ref="tns:R"/></xsd:sequence></xsd:complexType>)

      wrapper = body(field("n", "tns:N"), %{n: %{R: 2, g: 1}}, [], extra_types: extra)
      assert [%{children: [%{name: "g", text: "1"}, %{name: "R", text: "2", ns: "urn:t"}]}] = wrapper.children
    end

    test "a recursive type encodes" do
      extra =
        ~s(<xsd:complexType name="N"><xsd:sequence><xsd:element name="v" type="xsd:int"/><xsd:element name="next" type="tns:N" minOccurs="0"/></xsd:sequence></xsd:complexType>)

      wrapper = body(field("n", "tns:N"), %{n: %{v: 1, next: %{v: 2}}}, [], extra_types: extra)
      assert [%{children: [%{name: "v"}, %{name: "next", children: [%{name: "v", text: "2"}]}]}] = wrapper.children
    end

    test "a substitution group member can stand in for its head" do
      {:ok, service} =
        "synthetic/wsdl/substitution-group-inline.wsdl" |> Soap.Conformance.Support.corpus_path() |> Service.load()

      {:ok, operation} = Service.operation(service, "Draw")
      {:ok, %{xml: xml}} = Encoder.encode(service, operation, %{"Circle" => %{"id" => 1, "r" => 2.5}})
      assert xml =~ "Circle"
      assert xml =~ ">2.5<"
    end

    test "@xsi:type selects a subtype" do
      extra =
        ~s(<xsd:complexType name="B"><xsd:sequence><xsd:element name="b" type="xsd:string"/></xsd:sequence></xsd:complexType><xsd:complexType name="C"><xsd:complexContent><xsd:extension base="tns:B"><xsd:sequence><xsd:element name="c" type="xsd:string"/></xsd:sequence></xsd:extension></xsd:complexContent></xsd:complexType>)

      wrapper = body(field("n", "tns:B"), %{n: %{"@xsi:type" => "C", "b" => "1", "c" => "2"}}, [], extra_types: extra)
      assert [%{attrs: %{{@xsi, "type"} => {"urn:t", "C"}}, children: [_, _]}] = wrapper.children
    end
  end

  describe "SOAP headers" do
    test "qualifies a declared header by its element" do
      extra = ~s(<xsd:element name="Auth" type="xsd:string"/>)
      messages = ~s(<wsdl:message name="H"><wsdl:part name="auth" element="tns:Auth"/></wsdl:message>)

      doc =
        wsdl(extra_types: extra, input_extra: ~s(<soap:header message="tns:H" part="auth" use="literal"/>))
        |> String.replace(~s(<wsdl:portType), messages <> "<wsdl:portType")

      {:ok, service} = Service.from_string(doc)
      {:ok, operation} = Service.operation(service, "Pay")
      {:ok, %{xml: xml}} = Encoder.encode(service, operation, %{}, headers: %{"auth" => "t"})
      {:ok, envelope} = Xml.parse(xml)
      assert [%{ns: "urn:t", name: "Auth", text: "t"}] = Xml.header_children(envelope)
    end

    test "a {namespace, name} key names an undeclared header" do
      {:ok, %{xml: xml}} = encode(field("a", "xsd:string"), %{}, headers: [{{"urn:h", "Token"}, "t"}])
      {:ok, envelope} = Xml.parse(xml)
      assert [%{ns: "urn:h", name: "Token", text: "t"}] = Xml.header_children(envelope)
    end

    test "no headers means no Header element" do
      {:ok, %{xml: xml}} = encode(field("a", "xsd:string"), %{})
      {:ok, envelope} = Xml.parse(xml)
      assert Enum.map(envelope.children, & &1.name) == ["Body"]
    end
  end

  describe "SOAP versions" do
    test "uses each version's envelope" do
      {:ok, %{xml: v11}} = encode(field("a", "xsd:string"), %{})
      {:ok, %{xml: v12}} = encode(field("a", "xsd:string"), %{}, [], soap_uri: @soap12)
      assert {:ok, %{ns: "http://schemas.xmlsoap.org/soap/envelope/"}} = Xml.parse(v11)
      assert {:ok, %{ns: "http://www.w3.org/2003/05/soap-envelope"}} = Xml.parse(v12)
    end
  end

  describe "rpc" do
    defp rpc_service(use) do
      {:ok, service} =
        Service.from_string(
          ~s(<wsdl:definitions xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/" xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:enc="http://schemas.xmlsoap.org/soap/encoding/" xmlns:tns="urn:t" targetNamespace="urn:t">
          <wsdl:types><xsd:schema targetNamespace="urn:t"><xsd:complexType name="Names"><xsd:complexContent><xsd:restriction base="enc:Array"><xsd:attribute ref="enc:arrayType" wsdl:arrayType="xsd:string[]"/></xsd:restriction></xsd:complexContent></xsd:complexType></xsd:schema></wsdl:types>
          <wsdl:message name="In"><wsdl:part name="count" type="xsd:int"/><wsdl:part name="names" type="tns:Names"/></wsdl:message>
          <wsdl:portType name="PT"><wsdl:operation name="Op"><wsdl:input message="tns:In"/></wsdl:operation></wsdl:portType>
          <wsdl:binding name="B" type="tns:PT"><soap:binding style="rpc" transport="http://schemas.xmlsoap.org/soap/http"/><wsdl:operation name="Op"><soap:operation soapAction="a"/><wsdl:input><soap:body use="#{use}" namespace="urn:body" encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"/></wsdl:input></wsdl:operation></wsdl:binding>
        </wsdl:definitions>)
        )

      {:ok, operation} = Service.operation(service, "Op")
      {service, operation}
    end

    defp rpc_wrapper(use, params) do
      {service, operation} = rpc_service(use)
      {:ok, %{xml: xml}} = Encoder.encode(service, operation, params)
      {:ok, doc} = Xml.parse(xml)
      {:ok, [wrapper]} = Xml.body_children(doc)
      wrapper
    end

    test "literal: a wrapper named for the operation, with unqualified parts" do
      wrapper = rpc_wrapper("literal", %{count: 2})
      assert %{ns: "urn:body", name: "Op", children: [%{ns: nil, name: "count", text: "2", attrs: attrs}]} = wrapper
      assert attrs == %{}
    end

    test "encoded: adds encodingStyle and xsi:type" do
      wrapper = rpc_wrapper("encoded", %{count: 2})
      assert %{{"http://schemas.xmlsoap.org/soap/envelope/", "encodingStyle"} => _} = wrapper.attrs
      assert [%{attrs: %{{@xsi, "type"} => {"http://www.w3.org/2001/XMLSchema", "int"}}}] = wrapper.children
    end

    test "encoded: a soapenc:Array gets arrayType and item elements" do
      wrapper = rpc_wrapper("encoded", %{names: ["a", "b"]})

      assert [%{name: "names", attrs: attrs, children: [%{name: "item", text: "a"}, %{name: "item", text: "b"}]}] =
               wrapper.children

      assert attrs[{"http://schemas.xmlsoap.org/soap/encoding/", "arrayType"}] =~ "string[2]"
    end

    test "an unknown part is an error" do
      {service, operation} = rpc_service("literal")
      assert {:error, %Error{reason: {:invalid_param, "Op/nope", _}}} = Encoder.encode(service, operation, %{nope: 1})
    end
  end

  describe "attachments" do
    test "an Attachment value becomes an xop:Include" do
      attachment = %Attachment{data: "bytes", content_type: "text/plain"}
      {:ok, %{xml: xml, attachments: [sent]}} = encode(field("a", "xsd:base64Binary"), %{a: attachment})
      assert sent.id != nil
      assert sent.data == "bytes"
      assert xml =~ ~s(Include href="cid:#{sent.id}")
    end

    test "mtom: true moves base64 fields into attachments" do
      {:ok, %{xml: xml, attachments: [sent]}} = encode(field("a", "xsd:base64Binary"), %{a: "bytes"}, mtom: true)
      assert sent.data == "bytes"
      refute xml =~ Base.encode64("bytes")
    end

    test "without it, base64 stays inline" do
      {:ok, %{xml: xml, attachments: []}} = encode(field("a", "xsd:base64Binary"), %{a: "bytes"})
      assert xml =~ Base.encode64("bytes")
    end
  end

  test "output contains only the namespaces it uses" do
    {:ok, %{xml: xml}} = encode(field("a", "xsd:string"), %{a: "x"})
    refute xml =~ "XMLSchema"
    refute xml =~ "xop"
    assert xml =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
  end
end
