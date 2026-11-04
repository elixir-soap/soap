defmodule Soap.DecoderTest do
  use ExUnit.Case, async: true

  import Soap.Conformance.Support, only: [soap11: 1, soap12: 1, wsdl: 1]

  alias Soap.{Decoder, Error, Fault, Multipart, Service}
  alias Soap.Service.Operation

  defp plain(xml, status \\ 200, headers \\ []) do
    case Decoder.decode(nil, nil, status, headers, xml) do
      {:ok, decoded} -> {:ok, decoded.result}
      error -> error
    end
  end

  # A service whose output element PayOut has the given fields.
  defp typed(fields, inner, extra \\ "") do
    doc =
      wsdl(extra_types: extra)
      |> String.replace(
        ~s(<xsd:element name="result" type="xsd:string"/><xsd:element name="item" type="xsd:string" minOccurs="0" maxOccurs="unbounded"/>),
        fields
      )

    {:ok, service} = Service.from_string(doc)
    {:ok, operation} = Service.operation(service, "Pay")
    body = soap11(~s(<PayOut xmlns="urn:t" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">#{inner}</PayOut>))
    {:ok, %{result: %{"PayOut" => out}}} = Decoder.decode(service, operation, 200, [], body)
    out
  end

  defp field(name, type, extra \\ ""), do: ~s(<xsd:element name="#{name}" type="#{type}"#{extra}/>)

  describe "with no schema" do
    test "keys by local name, whatever the prefix" do
      assert plain(soap11(~s(<n:r xmlns:n="u"><n:v>1</n:v></n:r>))) == {:ok, %{"r" => %{"v" => "1"}}}
      assert plain(soap11(~s(<r xmlns="u"><v>1</v></r>))) == {:ok, %{"r" => %{"v" => "1"}}}
    end

    test "repeated elements are a list, single ones aren't" do
      assert plain(soap11("<r><i>1</i></r>")) == {:ok, %{"r" => %{"i" => "1"}}}
      assert plain(soap11("<r><i>1</i><i>2</i><i>3</i></r>")) == {:ok, %{"r" => %{"i" => ["1", "2", "3"]}}}
    end

    test "attributes and text" do
      assert plain(soap11(~s(<r><v a="1">t</v></r>))) == {:ok, %{"r" => %{"v" => %{"@a" => "1", "#text" => "t"}}}}
      assert plain(soap11(~s(<r><v a="1"/></r>))) == {:ok, %{"r" => %{"v" => %{"@a" => "1"}}}}
    end

    test "namespace declarations and encoding attributes aren't data" do
      xml =
        soap11(
          ~s(<r xmlns="u" xmlns:s="v" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" s:a="1" xsi:type="T"><v/></r>)
        )

      assert {:ok, %{"r" => %{"@a" => "1", "v" => nil}}} = plain(xml)
    end

    test "an empty element is nil, and xsi:nil is nil" do
      xml =
        soap11(
          ~s(<r xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><a/><b xsi:nil="true"/><c xsi:nil="1">x</c><d xsi:nil="false">x</d></r>)
        )

      assert plain(xml) == {:ok, %{"r" => %{"a" => nil, "b" => nil, "c" => nil, "d" => "x"}}}
    end

    test "keeps whitespace in text" do
      assert plain(soap11("<r> a\nb </r>")) == {:ok, %{"r" => " a\nb "}}
    end

    test "CDATA is text" do
      assert plain(soap11("<r><![CDATA[a<b]]></r>")) == {:ok, %{"r" => "a<b"}}
    end

    test "mixed content keeps both" do
      assert plain(soap11("<r>t<v>1</v></r>")) == {:ok, %{"r" => %{"v" => "1", "#text" => "t"}}}
    end

    test "xsi:type on a value gives it a type, even with no WSDL" do
      xml =
        soap11(
          ~s(<r xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:x="http://www.w3.org/2001/XMLSchema"><a xsi:type="x:int">5</a><b xsi:type="x:boolean">true</b></r>)
        )

      assert plain(xml) == {:ok, %{"r" => %{"a" => 5, "b" => true}}}
    end

    test "SOAP 1.2 replies decode the same" do
      assert plain(soap12("<r>1</r>")) == {:ok, %{"r" => "1"}}
    end

    test "an empty Body is nil" do
      assert plain(soap11("")) == {:ok, nil}
    end
  end

  describe "with a schema" do
    test "converts values by type" do
      fields = Enum.map_join(~w(int boolean double date dateTime time), "", &field("v#{&1}", "xsd:#{&1}"))

      out =
        typed(
          fields,
          "<vint>5</vint><vboolean>1</vboolean><vdouble>1.5</vdouble><vdate>2024-01-02</vdate><vdateTime>2024-01-02T03:04:05Z</vdateTime><vtime>03:04:05</vtime>"
        )

      assert out == %{
               "vint" => 5,
               "vboolean" => true,
               "vdouble" => 1.5,
               "vdate" => ~D[2024-01-02],
               "vdateTime" => ~U[2024-01-02 03:04:05Z],
               "vtime" => ~T[03:04:05]
             }
    end

    test "a dateTime with no zone is naive" do
      assert %{"t" => ~N[2024-01-02 03:04:05]} = typed(field("t", "xsd:dateTime"), "<t>2024-01-02T03:04:05</t>")
    end

    test "a value that doesn't parse stays a string" do
      assert %{"a" => "x", "d" => "2026-11-04+01:00", "b" => "maybe"} =
               typed(
                 field("a", "xsd:int") <> field("d", "xsd:date") <> field("b", "xsd:boolean"),
                 "<a>x</a><d>2026-11-04+01:00</d><b>maybe</b>"
               )
    end

    test "special floats, decimals, base64 and hex" do
      fields =
        field("f", "xsd:double", ~s( maxOccurs="unbounded")) <>
          field("d", "xsd:decimal") <> field("b", "xsd:base64Binary") <> field("h", "xsd:hexBinary")

      out = typed(fields, "<f>INF</f><f>-INF</f><f>NaN</f><d>12.50</d><b>AQL/</b><h>01ff</h>")
      assert out["f"] == [:infinity, :negative_infinity, :nan]
      assert Decimal.equal?(out["d"], Decimal.new("12.50"))
      assert out["b"] == <<1, 2, 255>>
      assert out["h"] == <<1, 255>>
    end

    test "a repeating element is a list, even with one item, and absent stays absent" do
      fields = field("r", "xsd:int", ~s( maxOccurs="unbounded")) <> field("o", "xsd:int", ~s( minOccurs="0"))
      assert typed(fields, "<r>1</r>") == %{"r" => [1]}
      assert typed(fields, "<r>1</r><r>2</r>") == %{"r" => [1, 2]}
      assert typed(fields, "<o>1</o>") == %{"o" => 1}
    end

    test "elements in a repeating group are lists too" do
      fields = ~s(<xsd:choice maxOccurs="unbounded">#{field("a", "xsd:int")}#{field("b", "xsd:int")}</xsd:choice>)
      assert typed(fields, "<a>1</a><b>2</b><a>3</a>") == %{"a" => [1, 3], "b" => [2]}
    end

    test "follows nested types, inheritance and declared attributes" do
      extra =
        ~s(<xsd:complexType name="B"><xsd:sequence>#{field("id", "xsd:int")}</xsd:sequence><xsd:attribute name="n" type="xsd:int"/></xsd:complexType><xsd:complexType name="C"><xsd:complexContent><xsd:extension base="tns:B"><xsd:sequence>#{field("x", "xsd:int")}</xsd:sequence></xsd:extension></xsd:complexContent></xsd:complexType>)

      assert typed(field("c", "tns:C"), ~s(<c n="7"><id>1</id><x>2</x></c>), extra) == %{
               "c" => %{"id" => 1, "x" => 2, "@n" => 7}
             }
    end

    test "xsi:type selects the subtype and is reported" do
      extra =
        ~s(<xsd:complexType name="B"><xsd:sequence>#{field("id", "xsd:int")}</xsd:sequence></xsd:complexType><xsd:complexType name="C"><xsd:complexContent><xsd:extension base="tns:B"><xsd:sequence>#{field("x", "xsd:int")}</xsd:sequence></xsd:extension></xsd:complexContent></xsd:complexType>)

      out = typed(field("b", "tns:B"), ~s(<b xmlns:t="urn:t" xsi:type="t:C"><id>1</id><x>2</x></b>), extra)
      assert out == %{"b" => %{"id" => 1, "x" => 2, "@xsi:type" => "C"}}
    end

    test "a real attribute named type isn't mistaken for it" do
      extra =
        ~s(<xsd:complexType name="B"><xsd:sequence/><xsd:attribute name="type" type="xsd:string"/></xsd:complexType><xsd:complexType name="C"><xsd:complexContent><xsd:extension base="tns:B"/></xsd:complexContent></xsd:complexType>)

      out = typed(field("b", "tns:B"), ~s(<b xmlns:t="urn:t" type="real" xsi:type="t:C"/>), extra)
      assert out == %{"b" => %{"@type" => "real", "@xsi:type" => "C"}}
    end

    test "a list type splits, and simple content keeps its attributes" do
      extra =
        ~s(<xsd:simpleType name="L"><xsd:list itemType="xsd:int"/></xsd:simpleType><xsd:complexType name="P"><xsd:simpleContent><xsd:extension base="xsd:decimal"><xsd:attribute name="cur" type="xsd:string"/></xsd:extension></xsd:simpleContent></xsd:complexType>)

      out = typed(field("l", "tns:L") <> field("p", "tns:P"), ~s(<l>1 2</l><p cur="EUR">1</p>), extra)
      assert out["l"] == [1, 2]
      assert %{"@cur" => "EUR", "#text" => _} = out["p"]
    end

    test "a recursive type decodes" do
      extra =
        ~s(<xsd:complexType name="N"><xsd:sequence>#{field("v", "xsd:int")}#{field("next", "tns:N", ~s( minOccurs="0"))}</xsd:sequence></xsd:complexType>)

      assert typed(field("n", "tns:N"), "<n><v>1</v><next><v>2</v></next></n>", extra) == %{
               "n" => %{"v" => 1, "next" => %{"v" => 2}}
             }
    end

    test "elements the schema doesn't know still come through" do
      assert typed(field("a", "xsd:int"), "<a>1</a><b>x</b>") == %{"a" => 1, "b" => "x"}
    end
  end

  describe "rpc/encoded" do
    @enc ~s(xmlns:e="http://schemas.xmlsoap.org/soap/envelope/" xmlns:enc="http://schemas.xmlsoap.org/soap/encoding/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:x="http://www.w3.org/2001/XMLSchema")

    defp encoded(inner), do: ~s(<e:Envelope #{@enc}><e:Body>#{inner}</e:Body></e:Envelope>)

    test "follows multiRef links and hides the targets" do
      xml =
        encoded(
          ~s(<R><value href="#id0"/></R><multiRef id="id0" enc:root="0"><a href="#id1"/></multiRef><multiRef id="id1" enc:root="0" xsi:type="x:int">5</multiRef>)
        )

      assert plain(xml) == {:ok, %{"R" => %{"value" => %{"a" => 5}}}}
    end

    test "a link cycle ends instead of hanging" do
      xml =
        encoded(
          ~s(<R><value href="#a"/></R><multiRef id="a" enc:root="0"><b href="#b"/></multiRef><multiRef id="b" enc:root="0"><a href="#a"/></multiRef>)
        )

      assert {:ok, %{"R" => %{"value" => %{"b" => %{"a" => nil}}}}} = plain(xml)
    end

    test "a link to nothing is left alone" do
      assert {:ok, %{"R" => %{"v" => _}}} = plain(encoded(~s(<R><v href="#missing"/></R>)))
    end

    test "soapenc arrays are lists" do
      xml = encoded(~s(<R enc:arrayType="x:string[2]"><i>a</i><i>b</i></R>))
      assert plain(xml) == {:ok, %{"R" => ["a", "b"]}}
    end

    test "SOAP 1.2 encoding references work" do
      xml =
        ~s(<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope" xmlns:enc="http://www.w3.org/2003/05/soap-encoding"><e:Body><R><v enc:ref="t"/></R><T id="t" enc:root="false">5</T></e:Body></e:Envelope>)

      assert plain(xml) == {:ok, %{"R" => %{"v" => "5"}}}
    end

    test "rpc output parts use their declared types" do
      service = %Service{}

      operation = %Operation{
        name: "Op",
        style: :rpc,
        version: "1.1",
        output: %Soap.Service.Message{
          parts: [%Soap.Service.Part{name: "r", type: {"http://www.w3.org/2001/XMLSchema", "int"}}]
        }
      }

      {:ok, decoded} = Decoder.decode(service, operation, 200, [], soap11("<OpResponse><r>5</r></OpResponse>"))
      assert decoded.result == %{"OpResponse" => %{"r" => 5}}
    end
  end

  describe "faults" do
    test "SOAP 1.1, with all fields" do
      xml =
        soap11(
          "<s:Fault><faultcode>s:Server</faultcode><faultstring>boom</faultstring><faultactor>me</faultactor><detail><why>x</why></detail></s:Fault>"
        )

      assert {:error, %Fault{code: "s:Server", message: "boom", actor: "me", detail: %{"why" => "x"}, status: 500}} =
               plain(xml, 500)
    end

    test "SOAP 1.2, with subcodes" do
      xml =
        soap12(
          ~s(<e:Fault><e:Code><e:Value>e:Sender</e:Value><e:Subcode><e:Value>a:One</e:Value><e:Subcode><e:Value>a:Two</e:Value></e:Subcode></e:Subcode></e:Code><e:Reason><e:Text xml:lang="en">nope</e:Text></e:Reason><e:Role>r</e:Role><e:Detail>d</e:Detail></e:Fault>)
        )

      assert {:error, %Fault{code: "e:Sender", subcodes: ["a:One", "a:Two"], message: "nope", actor: "r", detail: "d"}} =
               plain(xml, 400)
    end

    test "at any status" do
      xml = soap11("<s:Fault><faultcode>c</faultcode><faultstring>m</faultstring></s:Fault>")

      for status <- [200, 400, 500] do
        assert {:error, %Fault{status: ^status}} = plain(xml, status)
      end
    end

    test "a Fault is an exception" do
      assert Exception.message(%Fault{code: "c", message: "m"}) =~ "c: m"
    end
  end

  describe "errors" do
    test "broken replies at success statuses say what's wrong" do
      assert {:error, %Error{reason: {:invalid_xml, _}}} = plain("<a><b></a>")
      assert {:error, %Error{reason: :no_envelope}} = plain("<a>1</a>")
      assert {:error, %Error{reason: :doctype_not_allowed}} = plain(~s(<!DOCTYPE a [<!ENTITY x "y">]><a>&x;</a>))
    end

    test "anything at an error status is an HTTP error, with the body" do
      for body <- ["<html><body>x<br></body></html>", "<a/>", "text", soap11("<Err/>")] do
        assert {:error, %Error{reason: {:http_status, 502, ^body}}} = plain(body, 502)
      end
    end

    test "an empty body is fine on success and an error otherwise" do
      assert plain("", 200) == {:ok, nil}
      assert plain("", 202) == {:ok, nil}
      assert plain("  \n", 200) == {:ok, nil}
      assert {:error, %Error{reason: {:http_status, 500, ""}}} = plain("", 500)
    end
  end

  describe "SOAP headers" do
    test "are decoded and kept apart" do
      xml =
        ~s(<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Header><T xmlns="u">1</T></s:Header><s:Body><R>2</R></s:Body></s:Envelope>)

      assert {:ok, %{result: %{"R" => "2"}, soap_headers: %{"T" => "1"}}} = Decoder.decode(nil, nil, 200, [], xml)
    end
  end

  describe "transfer" do
    @reply soap11("<R>1</R>")

    test "gzip and deflate" do
      assert plain(:zlib.gzip(@reply), 200, [{"Content-Encoding", "gzip"}]) == {:ok, %{"R" => "1"}}
      assert plain(:zlib.compress(@reply), 200, [{"content-encoding", "deflate"}]) == {:ok, %{"R" => "1"}}
    end

    test "bad compression is an error" do
      assert {:error, %Error{reason: :invalid_compressed_body}} = plain("nope", 200, [{"content-encoding", "gzip"}])
    end

    test "MTOM parts resolve into the result" do
      soap = soap11(~s(<R><f><x:Include xmlns:x="http://www.w3.org/2004/08/xop/include" href="cid:a%40b"/></f></R>))
      {type, body} = Multipart.build(soap, [%Soap.Attachment{id: "a@b", data: <<0, 1, 2>>}], "text/xml")
      assert plain(IO.iodata_to_binary(body), 200, [{"Content-Type", type}]) == {:ok, %{"R" => %{"f" => <<0, 1, 2>>}}}
    end

    test "other parts are returned as attachments" do
      {type, body} =
        Multipart.build(@reply, [%Soap.Attachment{id: "z", data: "bytes", content_type: "text/plain"}], "text/xml")

      assert {:ok, %{result: %{"R" => "1"}, attachments: [%{id: "z", data: "bytes", content_type: "text/plain"}]}} =
               Decoder.decode(nil, nil, 200, [{"Content-Type", type}], IO.iodata_to_binary(body))
    end
  end
end
