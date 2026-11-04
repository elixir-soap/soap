defmodule Soap.Conformance.Xml do
  @moduledoc """
  A namespace-aware view of XML, for comparing documents by meaning.

  Two documents that differ only in prefixes, `xmlns` declarations, attribute order
  or whitespace between elements normalize to the same value. It is built on Saxy,
  so it creates no atoms and returns errors instead of exiting.

  A node is `%{ns: uri | nil, name: local, attrs: %{{ns, local} => value},
  children: [node], text: binary}`.
  """

  @xml_ns "http://www.w3.org/XML/1998/namespace"

  @spec parse(iodata()) :: {:ok, map()} | {:error, term()}
  def parse(xml) do
    case xml |> IO.iodata_to_binary() |> strip_bom() |> Saxy.SimpleForm.parse_string() do
      {:ok, tree} -> resolve(tree, %{"xml" => @xml_ns})
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "True when the document is well-formed and all its prefixes are bound."
  def valid?(xml), do: match?({:ok, _}, parse(xml))

  @doc "The children of the SOAP Body, or an error if there is no envelope."
  def body_children(%{name: "Envelope", children: children}) do
    case Enum.find(children, &(&1.name == "Body")) do
      nil -> {:error, :no_body}
      body -> {:ok, body.children}
    end
  end

  def body_children(_other), do: {:error, :no_envelope}

  @doc "The SOAP Header's children, or `[]`."
  def header_children(%{children: children}) do
    case Enum.find(children, &(&1.name == "Header")) do
      nil -> []
      header -> header.children
    end
  end

  @doc "A plain form of a node, for readable assertion diffs."
  def simplify(%{ns: ns, name: name, attrs: attrs, children: children, text: text}) do
    {ns, name, attrs, if(children == [], do: text, else: Enum.map(children, &simplify/1))}
  end

  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(binary), do: binary

  defp resolve({tag, attrs, content}, scope) do
    {declared, plain} = Enum.split_with(attrs, fn {k, _} -> k == "xmlns" or String.starts_with?(k, "xmlns:") end)

    scope =
      Enum.reduce(declared, scope, fn
        {"xmlns", uri}, acc -> Map.put(acc, "", uri)
        {"xmlns:" <> prefix, uri}, acc -> Map.put(acc, prefix, uri)
      end)

    with {:ok, ns, name} <- expand(tag, scope, true),
         {:ok, attrs} <- resolve_attrs(plain, scope),
         {:ok, children} <- resolve_children(content, scope) do
      text = content |> Enum.filter(&is_binary/1) |> Enum.join()
      text = if children == [] and String.trim(text) != "", do: text, else: ""
      {:ok, %{ns: blank_to_nil(ns), name: name, attrs: attrs, children: children, text: text}}
    end
  end

  defp resolve_attrs(attrs, scope) do
    Enum.reduce_while(attrs, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case expand(key, scope, false) do
        {:ok, ns, name} -> {:cont, {:ok, Map.put(acc, {ns, name}, value)}}
        error -> {:halt, error}
      end
    end)
  end

  defp resolve_children(content, scope) do
    content
    |> Enum.reject(&is_binary/1)
    |> Enum.reduce_while({:ok, []}, fn child, {:ok, acc} ->
      case resolve(child, scope) do
        {:ok, node} -> {:cont, {:ok, [node | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, nodes} -> {:ok, Enum.reverse(nodes)}
      error -> error
    end
  end

  defp expand(qname, scope, element?) do
    case String.split(qname, ":", parts: 2) do
      [prefix, local] ->
        case Map.fetch(scope, prefix) do
          {:ok, uri} -> {:ok, uri, local}
          :error -> {:error, {:unbound_prefix, prefix}}
        end

      [local] ->
        {:ok, if(element?, do: Map.get(scope, ""), else: nil), local}
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
