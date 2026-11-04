defmodule Soap.XML do
  @moduledoc """
  Parses XML into a namespace-aware tree of `Soap.XML.Element` structs.

  Built for documents from untrusted sources:

    * Names stay strings, so a document can't create atoms.
    * A DOCTYPE is refused, so external entities and entity bombs never apply.
    * Bad input returns `{:error, reason}` and never exits or raises.

  Real services also send documents that aren't strictly correct, so some problems
  are tolerated: whitespace before the XML declaration, a byte order mark, and
  prefixes that were never declared, which resolve to no namespace.
  """

  alias Soap.XML.Element

  @scan_limit 512

  @doc """
  Parses `xml`.

  ## Options

    * `:unknown_encoding` - what to do with a declared encoding this module can't
      convert. `:error` (the default) refuses non-ASCII input. `:latin1` reads it byte
      for byte, which suits WSDLs, where only comments tend to be non-ASCII.
  """
  @spec parse(binary(), keyword()) :: {:ok, Element.t()} | {:error, term()}
  def parse(xml, opts \\ []) when is_binary(xml) do
    with {:ok, utf8} <- to_utf8(xml, opts),
         {:ok, document} <- drop_declaration(String.trim_leading(utf8)),
         :ok <- check_prolog(document) do
      run_parser(document)
    end
  end

  # The bytes are UTF-8 by now, so a declared encoding no longer applies, and Saxy
  # refuses any declaration that names another one.
  defp drop_declaration(<<"<?xml", next, rest::binary>>) when next in [?\s, ?\t, ?\r, ?\n] do
    case :binary.split(rest, "?>") do
      [_, document] -> {:ok, String.trim_leading(document)}
      [_] -> {:error, {:invalid_xml, "unterminated XML declaration"}}
    end
  end

  defp drop_declaration(document), do: {:ok, document}

  defp run_parser(xml) do
    case Saxy.parse_string(xml, __MODULE__.Handler, %{stack: [], root: nil}, expand_entity: :keep) do
      {:ok, %{root: %Element{} = root}} -> {:ok, root}
      {:ok, _} -> {:error, {:invalid_xml, "no root element"}}
      {:error, error} -> {:error, {:invalid_xml, Exception.message(error)}}
    end
  rescue
    # Saxy reports most problems as values, but some truncated input raises instead.
    error -> {:error, {:invalid_xml, Exception.message(error)}}
  end

  # Encoding

  defp to_utf8(<<0xEF, 0xBB, 0xBF, rest::binary>>, _opts), do: check_utf8(rest)
  defp to_utf8(<<0xFF, 0xFE, rest::binary>>, _opts), do: from_utf16(rest, :little)
  defp to_utf8(<<0xFE, 0xFF, rest::binary>>, _opts), do: from_utf16(rest, :big)
  defp to_utf8(<<?<, 0, _::binary>> = xml, _opts), do: from_utf16(xml, :little)
  defp to_utf8(<<0, ?<, _::binary>> = xml, _opts), do: from_utf16(xml, :big)

  defp to_utf8(xml, opts) do
    case declared_encoding(xml) do
      encoding when encoding in [nil, "utf-8", "utf8", "us-ascii", "ascii"] -> check_utf8(xml)
      encoding when encoding in ["iso-8859-1", "iso8859-1", "latin1", "latin-1"] -> from_latin1(xml)
      encoding when encoding in ["utf-16", "utf16"] -> check_utf8(xml)
      encoding -> from_unknown(xml, encoding, opts)
    end
  end

  defp declared_encoding(xml) do
    head = binary_part(xml, 0, min(byte_size(xml), @scan_limit))

    case Regex.run(~r/^\s*<\?xml[^>]*?encoding\s*=\s*["']([A-Za-z0-9._-]+)["']/, head) do
      [_, encoding] -> String.downcase(encoding)
      nil -> nil
    end
  end

  defp check_utf8(xml) do
    if String.valid?(xml), do: {:ok, xml}, else: {:error, {:invalid_encoding, "not valid UTF-8"}}
  end

  defp from_utf16(xml, endian) do
    case :unicode.characters_to_binary(xml, {:utf16, endian}, :utf8) do
      utf8 when is_binary(utf8) -> {:ok, utf8}
      _ -> {:error, {:invalid_encoding, "not valid UTF-16"}}
    end
  end

  defp from_latin1(xml), do: {:ok, :unicode.characters_to_binary(xml, :latin1, :utf8)}

  defp from_unknown(xml, encoding, opts) do
    cond do
      ascii?(xml) -> {:ok, xml}
      opts[:unknown_encoding] == :latin1 -> from_latin1(xml)
      true -> {:error, {:unsupported_encoding, encoding}}
    end
  end

  defp ascii?(xml), do: for(<<byte <- xml>>, byte > 127, reduce: true, do: (_ -> false))

  # Refuses a DOCTYPE. Saxy would skip its internal subset, leaving entities unexpanded,
  # but a document that declares one has no place in a SOAP exchange.

  defp check_prolog(<<"<?", rest::binary>>), do: skip_until(rest, "?>")
  defp check_prolog(<<"<!--", rest::binary>>), do: skip_until(rest, "-->")
  defp check_prolog(<<"<!DOCTYPE", _::binary>>), do: {:error, :doctype_not_allowed}
  defp check_prolog(_xml), do: :ok

  defp skip_until(xml, marker) do
    case :binary.split(xml, marker) do
      [_, rest] -> rest |> String.trim_leading() |> check_prolog()
      [_] -> :ok
    end
  end

  defmodule Handler do
    @moduledoc false
    @behaviour Saxy.Handler

    @xml_ns "http://www.w3.org/XML/1998/namespace"

    @impl true
    def handle_event(:start_document, _prolog, state), do: {:ok, state}
    def handle_event(:end_document, _data, state), do: {:ok, state}

    def handle_event(:start_element, {tag, attributes}, state) do
      parent_scope =
        case state.stack do
          [%Element{scope: scope} | _] -> scope
          [] -> %{"xml" => @xml_ns}
        end

      {declarations, plain} = Enum.split_with(attributes, fn {name, _} -> namespace_declaration?(name) end)
      scope = Enum.reduce(declarations, parent_scope, &declare/2)
      {ns, local} = Element.expand(tag, scope, true)

      element = %Element{
        ns: ns,
        name: local,
        prefix: prefix_of(tag),
        scope: scope,
        attrs: Map.new(plain, fn {name, value} -> {Element.expand(name, scope, false), value} end)
      }

      {:ok, %{state | stack: [element | state.stack]}}
    end

    def handle_event(:characters, chars, %{stack: [top | rest]} = state) do
      {:ok, %{state | stack: [%{top | text: [top.text | chars]} | rest]}}
    end

    def handle_event(:characters, _chars, state), do: {:ok, state}

    def handle_event(:end_element, _tag, %{stack: [top | rest]} = state) do
      element = %{top | children: Enum.reverse(top.children), text: IO.iodata_to_binary(top.text)}

      case rest do
        [] -> {:ok, %{state | stack: [], root: element}}
        [parent | others] -> {:ok, %{state | stack: [%{parent | children: [element | parent.children]} | others]}}
      end
    end

    defp namespace_declaration?("xmlns"), do: true
    defp namespace_declaration?("xmlns:" <> _), do: true
    defp namespace_declaration?(_), do: false

    defp declare({"xmlns", ""}, scope), do: Map.delete(scope, "")
    defp declare({"xmlns", uri}, scope), do: Map.put(scope, "", uri)
    defp declare({"xmlns:", _uri}, scope), do: scope
    defp declare({"xmlns:" <> prefix, uri}, scope), do: Map.put(scope, prefix, uri)

    defp prefix_of(tag) do
      case String.split(tag, ":", parts: 2) do
        [prefix, _] -> prefix
        [_] -> nil
      end
    end
  end
end
