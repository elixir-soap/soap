defmodule Soap.SchemaTest do
  use ExUnit.Case, async: true

  alias Soap.Schema
  alias Soap.Schema.{Any, AttributeGroupRef, ComplexType, ElementDecl, Group, GroupRef, SimpleType}
  alias Soap.XML

  @xsd "http://www.w3.org/2001/XMLSchema"
  @enc "http://schemas.xmlsoap.org/soap/encoding/"

  defp schema(body, attrs \\ ~s(targetNamespace="urn:t" elementFormDefault="qualified"), opts \\ []) do
    xml =
      ~s(<xs:schema xmlns:xs="#{@xsd}" xmlns:t="urn:t" xmlns:enc="#{@enc}" xmlns:w="http://schemas.xmlsoap.org/wsdl/" #{attrs}>#{body}</xs:schema>)

    {:ok, root} = XML.parse(xml)
    Schema.read(root, opts)
  end

  describe "elements" do
    test "reads a global element with a named type" do
      s = schema(~s(<xs:element name="E" type="t:T" nillable="true"/>))

      assert %ElementDecl{name: "E", ns: "urn:t", type: {"urn:t", "T"}, nillable: true, global?: true} =
               Schema.element(s, {"urn:t", "E"})
    end

    test "reads an inline complex type" do
      s =
        schema(
          ~s(<xs:element name="E"><xs:complexType><xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence></xs:complexType></xs:element>)
        )

      assert %ElementDecl{type: nil, inline: %ComplexType{name: nil, content: %Group{kind: :sequence, items: [a]}}} =
               Schema.element(s, {"urn:t", "E"})

      assert %ElementDecl{name: "a", type: {@xsd, "string"}} = a
    end

    test "local elements follow elementFormDefault and the form attribute" do
      body =
        ~s(<xs:complexType name="T"><xs:sequence><xs:element name="a" type="xs:string"/><xs:element name="b" type="xs:string" form="unqualified"/></xs:sequence></xs:complexType>)

      q = schema(body) |> Schema.type({"urn:t", "T"})
      assert [%{name: "a", ns: "urn:t"}, %{name: "b", ns: nil}] = q.content.items

      u =
        schema(String.replace(body, ~s( form="unqualified"), ~s( form="qualified")), ~s(targetNamespace="urn:t"))
        |> Schema.type({"urn:t", "T"})

      assert [%{name: "a", ns: nil}, %{name: "b", ns: "urn:t"}] = u.content.items
    end

    test "a global element is always in the target namespace" do
      assert %{ns: "urn:t"} =
               schema(~s(<xs:element name="E" type="xs:string"/>), ~s(targetNamespace="urn:t"))
               |> Schema.element({"urn:t", "E"})
    end

    test "reads element references, occurrences and defaults" do
      body =
        ~s(<xs:complexType name="T"><xs:sequence><xs:element ref="t:R" minOccurs="0" maxOccurs="unbounded"/><xs:element name="x" type="xs:int" maxOccurs="3" default="5"/></xs:sequence></xs:complexType>)

      [r, x] = schema(body) |> Schema.type({"urn:t", "T"}) |> Map.fetch!(:content) |> Map.fetch!(:items)
      assert %{name: "R", ns: "urn:t", ref: {"urn:t", "R"}, min: 0, max: :unbounded} = r
      assert %{min: 1, max: 3, default: "5"} = x
    end

    test "reads substitution groups and abstract elements" do
      s =
        schema(
          ~s(<xs:element name="S" abstract="true" type="t:T"/><xs:element name="C" type="t:T" substitutionGroup="t:S"/>)
        )

      assert %{abstract: true} = Schema.element(s, {"urn:t", "S"})
      assert %{substitution_group: {"urn:t", "S"}} = Schema.element(s, {"urn:t", "C"})
    end
  end

  describe "complex types" do
    test "reads extension" do
      s =
        schema(
          ~s(<xs:complexType name="C" abstract="true"><xs:complexContent><xs:extension base="t:B"><xs:sequence><xs:element name="x" type="xs:int"/></xs:sequence><xs:attribute name="a" type="xs:string" use="required"/></xs:extension></xs:complexContent></xs:complexType>)
        )

      assert %ComplexType{
               base: {"urn:t", "B"},
               derivation: :extension,
               abstract: true,
               content: %Group{items: [_]},
               attributes: [%{name: "a", use: "required"}]
             } = Schema.type(s, {"urn:t", "C"})
    end

    test "reads simple content" do
      s =
        schema(
          ~s(<xs:complexType name="C"><xs:simpleContent><xs:extension base="xs:string"><xs:attribute name="lang" type="xs:string"/></xs:extension></xs:simpleContent></xs:complexType>)
        )

      assert %ComplexType{simple_content: true, base: {@xsd, "string"}, attributes: [%{name: "lang"}]} =
               Schema.type(s, {"urn:t", "C"})
    end

    test "reads choice, all, any and nested particles" do
      s =
        schema(
          ~s(<xs:complexType name="C"><xs:sequence><xs:choice minOccurs="0" maxOccurs="unbounded"><xs:element name="a" type="xs:int"/><xs:any namespace="##other" processContents="lax"/></xs:choice></xs:sequence><xs:anyAttribute/></xs:complexType><xs:complexType name="D"><xs:all><xs:element name="b" type="xs:int"/></xs:all></xs:complexType>)
        )

      assert %{
               any_attribute: true,
               content: %Group{
                 kind: :sequence,
                 items: [
                   %Group{
                     kind: :choice,
                     min: 0,
                     max: :unbounded,
                     items: [_, %Any{namespace: "##other", process_contents: "lax"}]
                   }
                 ]
               }
             } = Schema.type(s, {"urn:t", "C"})

      assert %{content: %Group{kind: :all}} = Schema.type(s, {"urn:t", "D"})
    end

    test "reads groups and attribute groups" do
      s =
        schema(
          ~s(<xs:group name="G"><xs:sequence><xs:element name="a" type="xs:int"/></xs:sequence></xs:group><xs:attributeGroup name="AG"><xs:attribute name="x" type="xs:int"/></xs:attributeGroup><xs:complexType name="C"><xs:sequence><xs:group ref="t:G" maxOccurs="2"/></xs:sequence><xs:attributeGroup ref="t:AG"/></xs:complexType>)
        )

      assert %{
               content: %Group{items: [%GroupRef{ref: {"urn:t", "G"}, max: 2}]},
               attributes: [%AttributeGroupRef{ref: {"urn:t", "AG"}}]
             } = Schema.type(s, {"urn:t", "C"})

      assert %Group{kind: :sequence} = s.groups[{"urn:t", "G"}]
      assert [%{name: "x"}] = s.attribute_groups[{"urn:t", "AG"}]
      assert Schema.unresolved_references(s) == []
    end

    test "reads a mixed type and a soapenc:Array" do
      s =
        schema(
          ~s(<xs:complexType name="M" mixed="true"/><xs:complexType name="A"><xs:complexContent><xs:restriction base="enc:Array"><xs:attribute ref="enc:arrayType" w:arrayType="xs:string[]"/></xs:restriction></xs:complexContent></xs:complexType>)
        )

      assert %{mixed: true} = Schema.type(s, {"urn:t", "M"})
      assert %{array_type: {@xsd, "string"}, derivation: :restriction} = Schema.type(s, {"urn:t", "A"})
    end
  end

  describe "simple types" do
    test "reads a restriction with facets" do
      s =
        schema(
          ~s(<xs:simpleType name="S"><xs:restriction base="xs:string"><xs:enumeration value="a"/><xs:enumeration value="b"/><xs:pattern value="[ab]"/><xs:maxLength value="1"/></xs:restriction></xs:simpleType>)
        )

      assert %SimpleType{
               variety: :atomic,
               base: {@xsd, "string"},
               enumeration: ["a", "b"],
               patterns: ["[ab]"],
               facets: %{max_length: "1"}
             } = Schema.type(s, {"urn:t", "S"})
    end

    test "reads a list and a union" do
      s =
        schema(
          ~s(<xs:simpleType name="L"><xs:list itemType="xs:int"/></xs:simpleType><xs:simpleType name="U"><xs:union memberTypes="xs:int t:L"><xs:simpleType><xs:restriction base="xs:string"/></xs:simpleType></xs:union></xs:simpleType>)
        )

      assert %{variety: :list, item_type: {@xsd, "int"}} = Schema.type(s, {"urn:t", "L"})

      assert %{variety: :union, member_types: [{@xsd, "int"}, {"urn:t", "L"}], inline_members: [%SimpleType{}]} =
               Schema.type(s, {"urn:t", "U"})
    end
  end

  describe "schema documents" do
    test "an included schema with no namespace takes on the includer's" do
      s =
        schema(
          ~s(<xs:element name="E" type="T"/><xs:complexType name="T"><xs:sequence><xs:element name="a" type="T"/></xs:sequence></xs:complexType>),
          "", target_namespace: "urn:i")

      assert %{ns: "urn:i", type: {"urn:i", "T"}} = Schema.element(s, {"urn:i", "E"})
      assert Schema.unresolved_references(s) == []
    end

    test "a schema with no namespace stays that way" do
      s = schema(~s(<xs:element name="E" type="xs:string"/>), "")
      assert %{ns: nil} = Schema.element(s, {nil, "E"})
    end

    test "xsd:redefine declarations are read, and later declarations win a merge" do
      first = schema(~s(<xs:complexType name="T"/>))
      second = schema(~s(<xs:redefine schemaLocation="x.xsd"><xs:complexType name="T" mixed="true"/></xs:redefine>))
      assert %{mixed: true} = first |> Schema.merge(second) |> Schema.type({"urn:t", "T"})
    end

    test "ignores annotations and unknown children" do
      s =
        schema(
          ~s(<xs:annotation><xs:documentation>x</xs:documentation></xs:annotation><other/><xs:notation name="n" public="p"/>)
        )

      assert s == %Schema{}
    end

    test "survives declarations with missing or bad attributes" do
      s =
        schema(
          ~s(<xs:complexType name="T"><xs:sequence><xs:element name="a" minOccurs="many"/><xs:group/></xs:sequence><xs:attributeGroup/></xs:complexType><xs:simpleType name="E"/>)
        )

      assert %{content: %Group{items: [%{min: 1}]}} = Schema.type(s, {"urn:t", "T"})
    end
  end

  describe "references" do
    test "reports what isn't declared, and accepts built-in types" do
      s =
        schema(
          ~s(<xs:element name="E" type="t:Missing"/><xs:element name="F" type="xs:string"/><xs:complexType name="T"><xs:complexContent><xs:extension base="t:Base"/></xs:complexContent></xs:complexType>)
        )

      assert Enum.sort(Schema.unresolved_references(s)) == [{"urn:t", "Base"}, {"urn:t", "Missing"}]
    end
  end
end
