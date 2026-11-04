defmodule Soap.XMLTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Soap.XML
  alias Soap.XML.Element

  describe "namespaces" do
    test "resolves prefixes, default namespaces and scoping" do
      {:ok, root} = XML.parse(~s(<a:r xmlns:a="u" xmlns="d"><x/><a:y xmlns="e"><z/></a:y></a:r>))
      assert {root.ns, root.name, root.prefix} == {"u", "r", "a"}
      [x, y] = root.children
      assert {x.ns, x.name} == {"d", "x"}
      assert {y.ns, y.name} == {"u", "y"}
      assert hd(y.children).ns == "e"
    end

    test "an unprefixed attribute has no namespace" do
      {:ok, root} = XML.parse(~s(<r xmlns="d" xmlns:p="u" a="1" p:b="2"/>))
      assert Element.attr(root, "a") == "1"
      assert Element.attr(root, "b") == nil
      assert Element.attr_ns(root, "u", "b") == "2"
    end

    test "namespace declarations are not attributes" do
      {:ok, root} = XML.parse(~s(<r xmlns="d" xmlns:p="u"/>))
      assert root.attrs == %{}
    end

    test "an empty default namespace undeclares it" do
      {:ok, root} = XML.parse(~s(<r xmlns="d"><x xmlns=""/></r>))
      assert hd(root.children).ns == nil
    end

    test "an undeclared prefix resolves to no namespace" do
      {:ok, root} = XML.parse(~s(<p:r q:a="1"/>))
      assert {root.ns, root.name} == {nil, "r"}
      assert root.attrs == %{{nil, "a"} => "1"}
    end

    test "resolves QName values" do
      {:ok, root} = XML.parse(~s(<r xmlns="d" xmlns:p="u" t="p:T"/>))
      assert Element.qname(root, "p:T") == {"u", "T"}
      assert Element.qname(root, "T") == {"d", "T"}
      assert Element.qname(root, "q:T") == {nil, "T"}
      assert Element.qname(root, nil) == nil
    end
  end

  describe "content" do
    test "collects text, CDATA and entities" do
      {:ok, root} = XML.parse("<r>a&lt;b<![CDATA[<c>&]]>&#233;</r>")
      assert root.text == "a<b<c>&é"
    end

    test "keeps whitespace in text" do
      {:ok, root} = XML.parse("<r> a\n\tb </r>")
      assert root.text == " a\n\tb "
    end

    test "finds children by namespace and name" do
      {:ok, root} = XML.parse(~s(<r xmlns="d"><a>1</a><a>2</a><b/></r>))
      assert root |> Element.children("d", "a") |> Enum.map(& &1.text) == ["1", "2"]
      assert Element.child(root, "d", "b").name == "b"
      assert Element.child(root, "other", "b") == nil
    end
  end

  describe "encodings" do
    test "UTF-8 with a byte order mark" do
      assert {:ok, %{text: "é"}} = XML.parse("﻿<r>é</r>")
    end

    test "UTF-16 in either byte order" do
      little = <<0xFF, 0xFE>> <> :unicode.characters_to_binary("<r>é</r>", :utf8, {:utf16, :little})
      big = <<0xFE, 0xFF>> <> :unicode.characters_to_binary("<r>é</r>", :utf8, {:utf16, :big})
      assert {:ok, %{text: "é"}} = XML.parse(little)
      assert {:ok, %{text: "é"}} = XML.parse(big)
    end

    test "ISO-8859-1" do
      head = ~s(<?xml version="1.0" encoding="ISO-8859-1"?><r>)
      assert {:ok, %{text: "é"}} = XML.parse(<<head::binary, 0xE9, "</r>">>)
    end

    test "an unknown encoding works for ASCII content only" do
      declaration = ~s(<?xml version="1.0" encoding="windows-1255"?>)
      assert {:ok, %{text: "a"}} = XML.parse(declaration <> "<r>a</r>")
      assert {:error, {:unsupported_encoding, "windows-1255"}} = XML.parse(<<declaration::binary, "<r>", 0xE9, "</r>">>)
    end

    test "an unknown encoding can be read as bytes" do
      head = ~s(<?xml version="1.0" encoding="windows-1255"?><r>)
      assert {:ok, %{text: "é"}} = XML.parse(<<head::binary, 0xE9, "</r>">>, unknown_encoding: :latin1)
    end

    test "invalid UTF-8 is an error" do
      assert {:error, {:invalid_encoding, _}} = XML.parse(<<"<r>", 0xFF, "</r>">>)
    end
  end

  describe "tolerance" do
    test "accepts whitespace before the XML declaration" do
      assert {:ok, %{name: "r"}} = XML.parse(~s(\n  <?xml version="1.0"?><r/>))
    end
  end

  describe "errors" do
    test "malformed documents" do
      for xml <- ["", "   ", "text", "<a><b></a>", "<a>", "<a></a><b></b>", "<html><body>503<br></body></html>"] do
        assert {:error, _} = XML.parse(xml), "expected an error for #{inspect(xml)}"
      end
    end

    test "a DOCTYPE is refused, wherever it sits in the prolog" do
      for xml <- [
            ~s(<!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd">]><r>&x;</r>),
            ~s(<?xml version="1.0"?>\n<!-- c --><!DOCTYPE r><r/>)
          ] do
        assert {:error, :doctype_not_allowed} = XML.parse(xml)
      end
    end

    test "a DOCTYPE mentioned in a comment is harmless" do
      assert {:ok, %{name: "r"}} = XML.parse("<!-- <!DOCTYPE x> --><r/>")
    end
  end

  describe "safety" do
    test "parsing creates no atoms" do
      suffix = System.unique_integer([:positive])
      tags = Enum.map_join(1..2_000, "", &"<xmlt#{suffix}n#{&1} a#{suffix}=\"1\"/>")
      before = :erlang.system_info(:atom_count)
      assert {:ok, _} = XML.parse("<r>#{tags}</r>")
      assert :erlang.system_info(:atom_count) - before < 50
    end

    property "any bytes return a result" do
      check all(bytes <- StreamData.binary(), max_runs: 300) do
        assert match?({:ok, %Element{}}, XML.parse(bytes)) or match?({:error, _}, XML.parse(bytes))
      end
    end

    property "any cut-off document returns a result" do
      doc = ~s(<?xml version="1.0"?><a:r xmlns:a="u"><b c="1">t&amp;x</b><![CDATA[y]]><!-- z --></a:r>)

      check all(cut <- StreamData.integer(0..(byte_size(doc) - 1)), max_runs: 200) do
        assert {:error, _} = XML.parse(binary_part(doc, 0, cut))
      end
    end
  end
end
