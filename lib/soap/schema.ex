defmodule Soap.Schema do
  @moduledoc """
  An XML Schema model: the global declarations of one or more `xsd:schema` documents.

  Declarations are keyed by `{namespace, local_name}`. `read/2` reads one document and
  `merge/2` combines documents. Importing and including other files is the loader's job.
  """

  alias Soap.Schema.{
    Any,
    AttributeDecl,
    AttributeGroupRef,
    ComplexType,
    ElementDecl,
    Group,
    GroupRef,
    SimpleType
  }

  alias Soap.XML.Element

  @xsd "http://www.w3.org/2001/XMLSchema"
  @wsdl "http://schemas.xmlsoap.org/wsdl/"
  @soap_enc "http://schemas.xmlsoap.org/soap/encoding/"
  @soap12_enc "http://www.w3.org/2003/05/soap-encoding"
  @builtin [@xsd, @soap_enc, @soap12_enc]

  defstruct elements: %{}, types: %{}, groups: %{}, attribute_groups: %{}, attributes: %{}

  @type qname :: {String.t() | nil, String.t()}
  @type t :: %__MODULE__{
          elements: %{qname() => ElementDecl.t()},
          types: %{qname() => ComplexType.t() | SimpleType.t()},
          groups: %{qname() => Group.t()},
          attribute_groups: %{qname() => list()},
          attributes: %{qname() => AttributeDecl.t()}
        }

  @doc "The XML Schema namespace."
  def xsd_namespace, do: @xsd

  @doc "The SOAP encoding namespace, which also defines types."
  def soap_encoding_namespace, do: @soap_enc

  @doc "True for a type defined by XML Schema or SOAP encoding rather than a document."
  def builtin?({ns, _name}), do: ns in @builtin

  @doc "Finds a global type."
  def type(%__MODULE__{types: types}, qname), do: Map.get(types, qname)

  @doc "Finds a global element."
  def element(%__MODULE__{elements: elements}, qname), do: Map.get(elements, qname)

  @doc "Combines two schemas. Declarations in `later` win, as `xsd:redefine` requires."
  def merge(%__MODULE__{} = earlier, %__MODULE__{} = later) do
    %__MODULE__{
      elements: Map.merge(earlier.elements, later.elements),
      types: Map.merge(earlier.types, later.types),
      groups: Map.merge(earlier.groups, later.groups),
      attribute_groups: Map.merge(earlier.attribute_groups, later.attribute_groups),
      attributes: Map.merge(earlier.attributes, later.attributes)
    }
  end

  @doc """
  Reads one `xsd:schema` element.

  ## Options

    * `:target_namespace` - used when the schema declares none. A schema pulled in by
      `xsd:include` this way takes on the namespace of the schema that includes it.
  """
  @spec read(Element.t(), keyword()) :: t()
  def read(%Element{} = schema, opts \\ []) do
    own = Element.attr(schema, "targetNamespace")

    ctx = %{
      target: own || opts[:target_namespace],
      chameleon: own == nil and opts[:target_namespace] != nil,
      element_form: Element.attr(schema, "elementFormDefault", "unqualified"),
      attribute_form: Element.attr(schema, "attributeFormDefault", "unqualified")
    }

    Enum.reduce(schema.children, %__MODULE__{}, &read_top_level(&1, &2, ctx))
  end

  @doc """
  Every type, element, group or attribute reference with no matching declaration.

  References into XML Schema and SOAP encoding count as resolved.
  """
  @spec unresolved_references(t()) :: [qname()]
  def unresolved_references(%__MODULE__{} = schema) do
    declarations = Map.values(schema.elements) ++ Map.values(schema.types)
    groups = Map.values(schema.groups)
    attribute_lists = Enum.concat(Map.values(schema.attribute_groups))

    (declarations ++ groups ++ attribute_lists)
    |> Enum.flat_map(&references/1)
    |> Enum.uniq()
    |> Enum.reject(&resolved?(schema, &1))
    |> Enum.map(fn {_kind, qname} -> qname end)
    |> Enum.uniq()
  end

  defp resolved?(_schema, {_kind, {ns, _}}) when ns in @builtin, do: true
  defp resolved?(_schema, {_kind, {"http://www.w3.org/XML/1998/namespace", _}}), do: true
  defp resolved?(schema, {:type, qname}), do: Map.has_key?(schema.types, qname)
  defp resolved?(schema, {:element, qname}), do: Map.has_key?(schema.elements, qname)
  defp resolved?(schema, {:group, qname}), do: Map.has_key?(schema.groups, qname)
  defp resolved?(schema, {:attribute_group, qname}), do: Map.has_key?(schema.attribute_groups, qname)
  defp resolved?(schema, {:attribute, qname}), do: Map.has_key?(schema.attributes, qname)

  defp references(%ElementDecl{} = e) do
    ref(:type, e.type) ++ ref(:element, e.ref) ++ references(e.inline)
  end

  defp references(%ComplexType{} = t) do
    ref(:type, t.base) ++ references(t.content) ++ Enum.flat_map(t.attributes, &references/1)
  end

  defp references(%SimpleType{} = t) do
    ref(:type, t.base) ++
      ref(:type, t.item_type) ++
      Enum.flat_map(t.member_types, &ref(:type, &1)) ++
      references(t.inline_item) ++ Enum.flat_map(t.inline_members, &references/1)
  end

  defp references(%Group{items: items}), do: Enum.flat_map(items, &references/1)
  defp references(%GroupRef{ref: ref}), do: ref(:group, ref)
  defp references(%AttributeGroupRef{ref: ref}), do: ref(:attribute_group, ref)
  defp references(%AttributeDecl{} = a), do: ref(:type, a.type) ++ ref(:attribute, a.ref) ++ references(a.inline)
  defp references(_other), do: []

  defp ref(_kind, nil), do: []
  defp ref(kind, qname), do: [{kind, qname}]

  # Top level

  defp read_top_level(%Element{ns: @xsd, name: name} = el, acc, ctx) do
    case name do
      "element" -> put(acc, :elements, global_element(el, ctx))
      "complexType" -> put(acc, :types, complex_type(el, ctx))
      "simpleType" -> put(acc, :types, simple_type(el, ctx))
      "attribute" -> put(acc, :attributes, global_attribute(el, ctx))
      "group" -> read_group_definition(el, acc, ctx)
      "attributeGroup" -> read_attribute_group_definition(el, acc, ctx)
      "redefine" -> Enum.reduce(el.children, acc, &read_top_level(&1, &2, ctx))
      _ -> acc
    end
  end

  defp read_top_level(_other, acc, _ctx), do: acc

  defp put(acc, field, declaration) do
    Map.update!(acc, field, &Map.put(&1, {declaration.ns, declaration.name}, declaration))
  end

  defp read_group_definition(el, acc, ctx) do
    case Enum.find_value(el.children, &particle(&1, ctx)) do
      nil -> acc
      group -> %{acc | groups: Map.put(acc.groups, {ctx.target, Element.attr(el, "name")}, group)}
    end
  end

  defp read_attribute_group_definition(el, acc, ctx) do
    key = {ctx.target, Element.attr(el, "name")}
    %{acc | attribute_groups: Map.put(acc.attribute_groups, key, attributes(el, ctx))}
  end

  # Elements

  defp global_element(el, ctx) do
    %{local_element(el, ctx) | ns: ctx.target, global?: true}
  end

  defp local_element(el, ctx) do
    ref = qualified(el, Element.attr(el, "ref"), ctx)
    {ref_ns, ref_name} = ref || {nil, nil}
    form = Element.attr(el, "form", ctx.element_form)

    %ElementDecl{
      name: Element.attr(el, "name") || ref_name,
      ns: if(ref, do: ref_ns, else: if(form == "qualified", do: ctx.target)),
      ref: ref,
      type: qualified(el, Element.attr(el, "type"), ctx),
      inline: inline_type(el, ctx),
      min: occurs(Element.attr(el, "minOccurs"), 1),
      max: occurs(Element.attr(el, "maxOccurs"), 1),
      nillable: Element.attr(el, "nillable") == "true",
      abstract: Element.attr(el, "abstract") == "true",
      default: Element.attr(el, "default"),
      fixed: Element.attr(el, "fixed"),
      substitution_group: qualified(el, Element.attr(el, "substitutionGroup"), ctx)
    }
  end

  defp inline_type(el, ctx) do
    Enum.find_value(el.children, fn
      %Element{ns: @xsd, name: "complexType"} = child -> complex_type(child, ctx)
      %Element{ns: @xsd, name: "simpleType"} = child -> simple_type(child, ctx)
      _ -> nil
    end)
  end

  # Complex types

  defp complex_type(el, ctx) do
    base = %ComplexType{
      name: Element.attr(el, "name"),
      ns: if(Element.attr(el, "name"), do: ctx.target),
      abstract: Element.attr(el, "abstract") == "true",
      mixed: Element.attr(el, "mixed") == "true"
    }

    case xsd_child(el, ["complexContent", "simpleContent"]) do
      nil ->
        %{base | content: first_particle(el, ctx), attributes: attributes(el, ctx), any_attribute: any_attribute?(el)}

      wrapper ->
        read_derived(base, wrapper, ctx)
    end
  end

  defp read_derived(type, wrapper, ctx) do
    case xsd_child(wrapper, ["extension", "restriction"]) do
      nil ->
        type

      derivation ->
        attrs = attributes(derivation, ctx)
        base = qualified(derivation, Element.attr(derivation, "base"), ctx)

        %{
          type
          | base: base,
            derivation: if(derivation.name == "extension", do: :extension, else: :restriction),
            simple_content: wrapper.name == "simpleContent",
            mixed: type.mixed or Element.attr(wrapper, "mixed") == "true",
            content: first_particle(derivation, ctx),
            attributes: attrs,
            any_attribute: any_attribute?(derivation),
            array_type: array_type(base, attrs)
        }
    end
  end

  # soapenc:Array restrictions name their item type in a wsdl:arrayType attribute.
  defp array_type({ns, "Array"}, attrs) when ns in [@soap_enc, @soap12_enc], do: Enum.find_value(attrs, &array_item/1)
  defp array_type(_base, _attrs), do: nil

  defp array_item(%AttributeDecl{array_type: item}), do: item
  defp array_item(_other), do: nil

  defp first_particle(el, ctx), do: Enum.find_value(el.children, &particle(&1, ctx))

  defp particle(%Element{ns: @xsd, name: name} = el, ctx) when name in ["sequence", "choice", "all"] do
    %Group{
      kind: group_kind(name),
      min: occurs(Element.attr(el, "minOccurs"), 1),
      max: occurs(Element.attr(el, "maxOccurs"), 1),
      items: el.children |> Enum.map(&item(&1, ctx)) |> Enum.reject(&is_nil/1)
    }
  end

  defp particle(%Element{ns: @xsd, name: "group"} = el, ctx), do: group_ref(el, ctx)
  defp particle(_other, _ctx), do: nil

  defp group_kind("sequence"), do: :sequence
  defp group_kind("choice"), do: :choice
  defp group_kind("all"), do: :all

  defp item(%Element{ns: @xsd, name: "element"} = el, ctx), do: local_element(el, ctx)

  defp item(%Element{ns: @xsd, name: "any"} = el, _ctx) do
    %Any{
      namespace: Element.attr(el, "namespace", "##any"),
      process_contents: Element.attr(el, "processContents", "strict"),
      min: occurs(Element.attr(el, "minOccurs"), 1),
      max: occurs(Element.attr(el, "maxOccurs"), 1)
    }
  end

  defp item(other, ctx), do: particle(other, ctx)

  defp group_ref(el, ctx) do
    case qualified(el, Element.attr(el, "ref"), ctx) do
      nil ->
        nil

      ref ->
        %GroupRef{
          ref: ref,
          min: occurs(Element.attr(el, "minOccurs"), 1),
          max: occurs(Element.attr(el, "maxOccurs"), 1)
        }
    end
  end

  # Attributes

  defp attributes(el, ctx) do
    Enum.flat_map(el.children, fn
      %Element{ns: @xsd, name: "attribute"} = child -> [local_attribute(child, ctx)]
      %Element{ns: @xsd, name: "attributeGroup"} = child -> attribute_group_ref(child, ctx)
      _ -> []
    end)
  end

  defp any_attribute?(el), do: xsd_child(el, ["anyAttribute"]) != nil

  defp attribute_group_ref(el, ctx) do
    case qualified(el, Element.attr(el, "ref"), ctx) do
      nil -> []
      ref -> [%AttributeGroupRef{ref: ref}]
    end
  end

  defp global_attribute(el, ctx), do: %{local_attribute(el, ctx) | ns: ctx.target}

  defp local_attribute(el, ctx) do
    ref = qualified(el, Element.attr(el, "ref"), ctx)
    {ref_ns, ref_name} = ref || {nil, nil}
    form = Element.attr(el, "form", ctx.attribute_form)

    %AttributeDecl{
      name: Element.attr(el, "name") || ref_name,
      ns: if(ref, do: ref_ns, else: if(form == "qualified", do: ctx.target)),
      ref: ref,
      type: qualified(el, Element.attr(el, "type"), ctx),
      inline: Enum.find_value(el.children, &simple_type_child(&1, ctx)),
      use: Element.attr(el, "use", "optional"),
      default: Element.attr(el, "default"),
      fixed: Element.attr(el, "fixed"),
      array_type: wsdl_array_type(el, ctx)
    }
  end

  defp simple_type_child(%Element{ns: @xsd, name: "simpleType"} = el, ctx), do: simple_type(el, ctx)
  defp simple_type_child(_other, _ctx), do: nil

  defp wsdl_array_type(el, ctx) do
    case Element.attr_ns(el, @wsdl, "arrayType") do
      nil -> nil
      value -> qualified(el, value |> String.split("[") |> hd(), ctx)
    end
  end

  # Simple types

  defp simple_type(el, ctx) do
    type = %SimpleType{name: Element.attr(el, "name"), ns: if(Element.attr(el, "name"), do: ctx.target)}

    case xsd_child(el, ["restriction", "list", "union"]) do
      %Element{name: "restriction"} = r -> read_restriction(type, r, ctx)
      %Element{name: "list"} = l -> read_list(type, l, ctx)
      %Element{name: "union"} = u -> read_union(type, u, ctx)
      nil -> type
    end
  end

  defp read_restriction(type, el, ctx) do
    facets = el.children |> Enum.filter(&(&1.ns == @xsd)) |> Enum.reduce(%{}, &read_facet/2)

    %{
      type
      | variety: :atomic,
        base: qualified(el, Element.attr(el, "base"), ctx),
        inline_item: Enum.find_value(el.children, &simple_type_child(&1, ctx)),
        enumeration: facets |> Map.get(:enumeration, []) |> Enum.reverse(),
        patterns: facets |> Map.get(:pattern, []) |> Enum.reverse(),
        facets: Map.drop(facets, [:enumeration, :pattern])
    }
  end

  @facets %{
    "length" => :length,
    "minLength" => :min_length,
    "maxLength" => :max_length,
    "minInclusive" => :min_inclusive,
    "maxInclusive" => :max_inclusive,
    "minExclusive" => :min_exclusive,
    "maxExclusive" => :max_exclusive,
    "totalDigits" => :total_digits,
    "fractionDigits" => :fraction_digits,
    "whiteSpace" => :white_space
  }

  defp read_facet(%Element{name: "enumeration"} = el, acc) do
    Map.update(acc, :enumeration, [Element.attr(el, "value")], &[Element.attr(el, "value") | &1])
  end

  defp read_facet(%Element{name: "pattern"} = el, acc) do
    Map.update(acc, :pattern, [Element.attr(el, "value")], &[Element.attr(el, "value") | &1])
  end

  defp read_facet(%Element{name: name} = el, acc) do
    case @facets do
      %{^name => key} -> Map.put(acc, key, Element.attr(el, "value"))
      _ -> acc
    end
  end

  defp read_list(type, el, ctx) do
    %{
      type
      | variety: :list,
        item_type: qualified(el, Element.attr(el, "itemType"), ctx),
        inline_item: Enum.find_value(el.children, &simple_type_child(&1, ctx))
    }
  end

  defp read_union(type, el, ctx) do
    members = el |> Element.attr("memberTypes", "") |> String.split()

    %{
      type
      | variety: :union,
        member_types: Enum.map(members, &qualified(el, &1, ctx)),
        inline_members: Enum.flat_map(el.children, &List.wrap(simple_type_child(&1, ctx)))
    }
  end

  # Helpers

  defp xsd_child(el, names), do: Enum.find(el.children, &(&1.ns == @xsd and &1.name in names))

  # Unprefixed references in an included schema with no namespace take on the
  # namespace of the schema that includes it.
  defp qualified(_el, nil, _ctx), do: nil

  defp qualified(el, value, ctx) do
    case Element.qname(el, value) do
      {nil, local} when ctx.chameleon -> {ctx.target, local}
      # A schema in a WSDL whose default namespace is the WSDL's. No schema type lives
      # there, so an unprefixed reference can only mean this schema's own namespace.
      {@wsdl, local} -> {ctx.target, local}
      qname -> qname
    end
  end

  defp occurs(nil, default), do: default
  defp occurs("unbounded", _default), do: :unbounded

  defp occurs(value, default) do
    case Integer.parse(String.trim(value)) do
      {number, ""} when number >= 0 -> number
      _ -> default
    end
  end
end
