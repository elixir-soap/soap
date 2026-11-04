defmodule Soap.XML.Element do
  @moduledoc """
  One XML element, with namespaces resolved.

  `scope` holds the prefixes in force at this element, which is needed to read values
  that are themselves qualified names, such as `type="xsd:string"`.
  """

  defstruct [:ns, :name, :prefix, attrs: %{}, children: [], text: [], scope: %{}]

  @type qname :: {String.t() | nil, String.t()}

  @type t :: %__MODULE__{
          ns: String.t() | nil,
          name: String.t(),
          prefix: String.t() | nil,
          attrs: %{qname() => String.t()},
          children: [t()],
          text: binary() | iodata(),
          scope: %{String.t() => String.t()}
        }

  @doc "Reads an attribute that has no namespace."
  @spec attr(t(), String.t(), term()) :: String.t() | term()
  def attr(%__MODULE__{attrs: attrs}, name, default \\ nil), do: Map.get(attrs, {nil, name}, default)

  @doc "Reads an attribute in namespace `ns`."
  @spec attr_ns(t(), String.t(), String.t()) :: String.t() | nil
  def attr_ns(%__MODULE__{attrs: attrs}, ns, name), do: Map.get(attrs, {ns, name})

  @doc "Child elements with this namespace and local name."
  @spec children(t(), String.t() | nil, String.t()) :: [t()]
  def children(%__MODULE__{children: children}, ns, name) do
    Enum.filter(children, &(&1.ns == ns and &1.name == name))
  end

  @doc "The first child element with this namespace and local name."
  @spec child(t(), String.t() | nil, String.t()) :: t() | nil
  def child(%__MODULE__{children: children}, ns, name) do
    Enum.find(children, &(&1.ns == ns and &1.name == name))
  end

  @doc "Resolves a QName value such as `tns:Foo` using this element's prefixes."
  @spec qname(t(), String.t() | nil) :: qname() | nil
  def qname(_element, nil), do: nil
  def qname(%__MODULE__{scope: scope}, value), do: value |> String.trim() |> expand(scope, true)

  @doc """
  Expands a prefixed name into `{namespace, local}`.

  A prefix that was never declared resolves to no namespace. Only elements and QName
  values take the default namespace.
  """
  @spec expand(String.t(), map(), boolean()) :: qname()
  def expand(name, scope, use_default?) do
    case String.split(name, ":", parts: 2) do
      [prefix, local] -> {Map.get(scope, prefix), local}
      [local] -> {if(use_default?, do: Map.get(scope, "")), local}
    end
  end
end
