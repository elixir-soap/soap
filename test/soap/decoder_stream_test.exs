defmodule Soap.DecoderStreamTest do
  @moduledoc """
  Most replies decode during parsing, and the rest through a tree. These tests check that
  both give the same answer on every reply in the corpus and on generated ones.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Soap.Conformance.Support, only: [corpus_path: 1, soap11: 1, soap12: 1, wsdl: 1]

  alias Soap.{Decoder, Service}

  @xsi "http://www.w3.org/2001/XMLSchema-instance"

  defp same_answer(service, operation, body, status \\ 200, headers \\ []) do
    assert Decoder.decode(service, operation, status, headers, body) ==
             Decoder.decode(service, operation, status, headers, body, tree: true)
  end

  defp streamed?(body, service \\ nil, operation \\ nil) do
    Decoder.decode_while_parsing(body, [], service, operation) != :needs_tree
  end

  defp typed_service do
    fields = ~s(
      <xsd:element name="result" type="xsd:string" minOccurs="0"/>
      <xsd:element name="count" type="xsd:int" minOccurs="0"/>
      <xsd:element name="flag" type="xsd:boolean" minOccurs="0"/>
      <xsd:element name="when" type="xsd:date" minOccurs="0"/>
      <xsd:element name="item" type="xsd:string" minOccurs="0" maxOccurs="unbounded"/>
      <xsd:element name="codes" type="tns:Codes" minOccurs="0" maxOccurs="unbounded"/>
      <xsd:element ref="tns:head" minOccurs="0" maxOccurs="unbounded"/>
      <xsd:element name="dup" type="xsd:int" minOccurs="0"/>
      <xsd:element name="dup" type="xsd:string" minOccurs="0"/>
      <xsd:element name="nested" type="tns:Nested" minOccurs="0" maxOccurs="unbounded"/>
    )

    nested = ~s(
      <xsd:simpleType name="Codes"><xsd:list itemType="xsd:int"/></xsd:simpleType>
      <xsd:element name="head" type="xsd:string" abstract="true"/>
      <xsd:element name="stand_in" type="xsd:int" substitutionGroup="tns:head"/>
      <xsd:complexType name="Nested"><xsd:sequence>
        <xsd:element name="count" type="xsd:int" minOccurs="0"/>
        <xsd:element name="nested" type="tns:Nested" minOccurs="0"/>
      </xsd:sequence><xsd:attribute name="size" type="xsd:int"/></xsd:complexType>
      <xsd:complexType name="Wider"><xsd:complexContent><xsd:extension base="tns:Nested"><xsd:sequence>
        <xsd:element name="extra" type="xsd:int" minOccurs="0"/>
      </xsd:sequence></xsd:extension></xsd:complexContent></xsd:complexType>
    )

    doc =
      [extra_types: nested]
      |> wsdl()
      |> String.replace(
        ~s(<xsd:element name="result" type="xsd:string"/><xsd:element name="item" type="xsd:string" minOccurs="0" maxOccurs="unbounded"/>),
        fields
      )

    assert doc =~ ~s(name="flag")
    {:ok, service} = Service.from_string(doc)
    {:ok, operation} = Service.operation(service, "Pay")
    {service, operation}
  end

  describe "which replies decode during parsing" do
    test "ordinary replies do" do
      assert streamed?(soap11("<R><a>1</a><a>2</a></R>"))
      assert streamed?(soap12(~s(<R x="1">text</R>)))
      assert streamed?(soap11(""))
    end

    test "anything that needs the whole document doesn't" do
      refute streamed?(soap11(~s(<soap:Fault xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"/>)))
      refute streamed?(soap11(~s(<R><a href="#1"/></R><multiRef id="1">x</multiRef>)))

      refute streamed?(
               soap11(~s(<R><f><x:Include xmlns:x="http://www.w3.org/2004/08/xop/include" href="cid:a"/></f></R>))
             )

      refute streamed?(
               soap11(~s(<R xmlns:e="http://schemas.xmlsoap.org/soap/encoding/" e:arrayType="x[1]"><i>1</i></R>))
             )

      refute streamed?("<notsoap/>")
      refute streamed?("<broken")
    end
  end

  describe "the same answer as the tree" do
    test "for every reply in the corpus" do
      paths =
        Path.wildcard(corpus_path("golden/php-interop/*.xml")) ++
          Path.wildcard(corpus_path("golden/node-soap/**/*.xml")) ++
          Path.wildcard(corpus_path("recordings/*/response.body")) ++
          Path.wildcard(corpus_path("negative/**/*.xml"))

      assert length(paths) > 400

      for path <- paths, body = File.read!(path), status <- [200, 500] do
        same_answer(nil, nil, body, status)
      end
    end

    test "with a schema, for the shapes it treats differently" do
      {service, operation} = typed_service()

      for inner <- [
            "",
            "<result>x</result>",
            "<count>5</count><flag>true</flag><when>2020-01-02</when>",
            "<count>nope</count>",
            "<item>a</item>",
            "<item>a</item><item>b</item>",
            "<codes>1 2</codes>",
            "<codes>1 2</codes><codes>3</codes>",
            "<stand_in>4</stand_in>",
            "<dup>4</dup>",
            "<unknown>u</unknown>",
            "<nested><count>1</count></nested>",
            ~s(<nested size="3"><count>1</count><nested><count>2</count></nested></nested>),
            ~s(<nested xsi:type="tns:Wider" xmlns:tns="urn:t"><extra>9</extra></nested>),
            ~s(<nested xsi:nil="true"><count>1</count></nested>),
            ~s(<count xsi:nil="1"/>),
            ~s(<result xsi:type="xsd:int" xmlns:xsd="http://www.w3.org/2001/XMLSchema">7</result>),
            "text around <result>x</result> children",
            "<result><![CDATA[<raw>]]></result>",
            "<result> &amp; </result><!-- comment -->"
          ] do
        same_answer(service, operation, soap11(~s(<PayOut xmlns="urn:t" xmlns:xsi="#{@xsi}">#{inner}</PayOut>)))
      end
    end

    test "for envelopes of unusual shape" do
      env = ~s(xmlns:s="http://schemas.xmlsoap.org/soap/envelope/")

      for body <- [
            ~s(<s:Envelope #{env}/>),
            ~s(<s:Envelope #{env}><s:Body/></s:Envelope>),
            ~s(<s:Envelope #{env}><s:Header><H>1</H></s:Header></s:Envelope>),
            ~s(<s:Envelope #{env}><s:Body><R>1</R></s:Body><s:Header><H>1</H><H>2</H></s:Header></s:Envelope>),
            ~s(<s:Envelope #{env}><s:Header/><s:Body>loose text<R>1</R><R>2</R></s:Body></s:Envelope>),
            ~s(<s:Envelope #{env}><s:Body><A>1</A></s:Body><s:Body><B>2</B></s:Body></s:Envelope>),
            ~s(<s:Envelope #{env}><Body><R>1</R></Body></s:Envelope>),
            ~s(<s:Envelope #{env}><other/><s:Body><R>1</R></s:Body></s:Envelope>),
            ~s(<s:Envelope #{env}><s:Body><R>1</R></s:Body></s:Envelope><trailing/>),
            ~s(<s:Envelope #{env}><s:Body><R>1</s:Body></s:Envelope>),
            ~s(<?xml version="1.0" encoding="ISO-8859-1"?><s:Envelope #{env}><s:Body><R>\xE9</R></s:Body></s:Envelope>),
            ~s(<!DOCTYPE x><s:Envelope #{env}/>)
          ] do
        same_answer(nil, nil, body)
      end
    end
  end

  defp text_gen, do: member_of(["", " ", "x", "\n  ", "5", "true", "2020-01-02", "a &amp; b", "<![CDATA[<c>]]>"])
  defp name_gen, do: member_of(~w(result count flag when item codes stand_in nested extra unknown))

  defp attrs_gen do
    member_of([
      "",
      "",
      "",
      ~s( size="4"),
      ~s( id="i1"),
      ~s( xsi:nil="true"),
      ~s( xsi:type="xsd:int"),
      ~s( xsi:type="tns:Wider"),
      ~s( xsi:type="tns:Missing"),
      ~s( other:thing="v"),
      ~s( xmlns:more="urn:more")
    ])
  end

  defp element_gen do
    tree(
      bind({name_gen(), attrs_gen(), text_gen()}, fn {name, attrs, text} ->
        constant("<#{name}#{attrs}>#{text}</#{name}>")
      end),
      fn children ->
        bind({name_gen(), attrs_gen(), list_of(children, max_length: 4), text_gen()}, fn {name, attrs, kids, text} ->
          constant("<#{name}#{attrs}>#{text}#{Enum.join(kids)}</#{name}>")
        end)
      end
    )
  end

  property "generated replies give the same answer, with a schema and without" do
    {service, operation} = typed_service()

    namespaces =
      ~s(xmlns="urn:t" xmlns:tns="urn:t" xmlns:xsi="#{@xsi}" xmlns:other="urn:o" xmlns:xsd="http://www.w3.org/2001/XMLSchema")

    check all(children <- list_of(element_gen(), max_length: 6), max_runs: 300) do
      body = soap11(~s(<PayOut #{namespaces}>#{Enum.join(children)}</PayOut>))
      same_answer(service, operation, body)
      same_answer(nil, nil, body)
    end
  end
end
