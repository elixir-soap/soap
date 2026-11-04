defmodule Soap.Schema.Walk do
  @moduledoc """
  Answers questions about a `Soap.Schema` that need more than one declaration: the
  fields of a type once inheritance and groups are expanded, and what a simple type
  ultimately derives from.
  """

  alias Soap.Schema

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

  defmodule Field do
    @moduledoc """
    One element a type can contain, with its references resolved.

    `order` is its position in the schema. Fields inside a repeating group or an `all`
    share a position, because they may appear in any order. `repeats` is true when the
    field can occur more than once, including through a repeating group.
    """
    defstruct [:name, :ns, :type, :inline, :min, :max, :order, :repeats, :nillable, :abstract, :global_ref]
    @type t :: %__MODULE__{}
  end

  @doc "Finds a type by its full name, or by its local name if a prefix was bound carelessly."
  @spec find_type(Schema.t(), Schema.qname() | nil) :: ComplexType.t() | SimpleType.t() | nil
  def find_type(_schema, nil), do: nil

  def find_type(%Schema{types: types}, {_ns, local} = qname) do
    Map.get(types, qname) || unless(Schema.builtin?(qname), do: find_local(types, local))
  end

  @doc "Finds a global element by its full name, or by its local name."
  @spec find_element(Schema.t(), Schema.qname() | nil) :: ElementDecl.t() | nil
  def find_element(_schema, nil), do: nil

  def find_element(%Schema{elements: elements}, {_ns, local} = qname) do
    Map.get(elements, qname) || find_local(elements, local)
  end

  defp find_local(map, local) do
    Enum.find_value(map, fn {{_ns, name}, value} -> if name == local, do: value end)
  end

  @doc """
  The type of a declared element or field: a `ComplexType`, a `SimpleType`,
  `{:builtin, name}`, or nil if it's unknown.
  """
  def type_of(_schema, %{inline: inline}) when not is_nil(inline), do: inline
  def type_of(schema, %{type: qname}), do: resolve(schema, qname)

  @doc "Resolves a type name the same way as `type_of/2`."
  def resolve(_schema, nil), do: nil

  def resolve(schema, {_ns, local} = qname) do
    if Schema.builtin?(qname), do: {:builtin, local}, else: find_type(schema, qname) || type_of_element(schema, qname)
  end

  # Some schemas name a global element where a type belongs.
  defp type_of_element(schema, qname) do
    case Map.get(schema.elements, qname) do
      %ElementDecl{inline: inline} when not is_nil(inline) -> inline
      _ -> nil
    end
  end

  @doc """
  Every element a complex type can contain, base types first, and whether it also allows
  elements it doesn't name.
  """
  @spec fields(Schema.t(), ComplexType.t()) :: {[Field.t()], open? :: boolean()}
  def fields(schema, %ComplexType{} = type) do
    {items, open?} = collect_type(schema, type, MapSet.new())
    {number(items), open?}
  end

  defp collect_type(schema, %ComplexType{} = type, seen) do
    key = {type.ns, type.name}

    if type.name != nil and MapSet.member?(seen, key) do
      {[], false}
    else
      seen = if type.name, do: MapSet.put(seen, key), else: seen
      {inherited, inherited_open?} = collect_base(schema, type, seen)
      {own, own_open?} = collect_particle(schema, type.content, seen, false)
      {inherited ++ own, inherited_open? or own_open?}
    end
  end

  # A restriction restates its content, so only an extension inherits it.
  defp collect_base(schema, %ComplexType{derivation: :extension, base: base}, seen) do
    case resolve(schema, base) do
      %ComplexType{} = parent -> collect_type(schema, parent, seen)
      _ -> {[], false}
    end
  end

  defp collect_base(schema, %ComplexType{derivation: :restriction, base: base, content: nil}, seen) do
    case resolve(schema, base) do
      %ComplexType{} = parent -> collect_type(schema, parent, seen)
      _ -> {[], false}
    end
  end

  defp collect_base(_schema, _type, _seen), do: {[], false}

  defp collect_particle(_schema, nil, _seen, _repeating?), do: {[], false}

  defp collect_particle(schema, %Group{} = group, seen, repeating?) do
    repeating? = repeating? or many?(group.max)

    {items, open?} =
      Enum.reduce(group.items, {[], false}, fn item, {acc, open?} ->
        {found, found_open?} = collect_particle(schema, item, seen, repeating?)
        {acc ++ found, open? or found_open?}
      end)

    shared? = repeating? or group.kind == :all
    {if(shared?, do: Enum.map(items, &{:shared, group, &1}), else: mark_optional(items, group)), open?}
  end

  defp collect_particle(schema, %GroupRef{ref: ref} = group_ref, seen, repeating?) do
    key = {:group, ref}

    if MapSet.member?(seen, key) do
      {[], false}
    else
      target = Map.get(schema.groups, ref)
      collect_particle(schema, target, MapSet.put(seen, key), repeating? or many?(group_ref.max))
    end
  end

  defp collect_particle(schema, %ElementDecl{} = decl, _seen, repeating?) do
    {[field(schema, decl, repeating?)], false}
  end

  defp collect_particle(_schema, %Any{}, _seen, _repeating?), do: {[], true}

  # Only one member of a choice appears, so none of them is required.
  defp mark_optional(items, %Group{kind: :choice}) do
    Enum.map(items, fn
      %Field{} = field -> %{field | min: 0}
      other -> other
    end)
  end

  defp mark_optional(items, _group), do: items

  defp field(_schema, %ElementDecl{ref: nil} = decl, repeating?) do
    %Field{
      name: decl.name,
      ns: decl.ns,
      type: decl.type,
      inline: decl.inline,
      min: decl.min,
      max: decl.max,
      nillable: decl.nillable,
      abstract: decl.abstract,
      repeats: repeating? or many?(decl.max)
    }
  end

  defp field(schema, %ElementDecl{ref: ref} = decl, repeating?) do
    target = find_element(schema, ref)

    %Field{
      name: decl.name,
      ns: decl.ns,
      type: target && target.type,
      inline: target && target.inline,
      min: decl.min,
      max: decl.max,
      nillable: (target && target.nillable) || decl.nillable,
      abstract: target != nil and target.abstract,
      global_ref: ref,
      repeats: repeating? or many?(decl.max)
    }
  end

  defp many?(:unbounded), do: true
  defp many?(max), do: max > 1

  # Gives fields a position. Everything from one repeating group or `all` shares one.
  defp number(items) do
    {fields, _} =
      Enum.flat_map_reduce(items, {0, nil}, fn
        {:shared, group, inner}, {position, previous} ->
          position = if group == previous, do: position, else: position + 1
          {flatten_shared(inner, position), {position, group}}

        %Field{} = field, {position, _previous} ->
          {[%{field | order: position + 1}], {position + 1, nil}}
      end)

    fields
  end

  defp flatten_shared({:shared, _group, inner}, position), do: flatten_shared(inner, position)
  defp flatten_shared(%Field{} = field, position), do: [%{field | order: position}]

  @doc "Elements declared as able to stand in for `head`, directly or through another."
  @spec substitutes(Schema.t(), Schema.qname()) :: [ElementDecl.t()]
  def substitutes(%Schema{elements: elements}, head) do
    direct = for {_key, decl} <- elements, decl.substitution_group == head, do: decl
    direct ++ Enum.flat_map(direct, &substitutes(%Schema{elements: elements}, {&1.ns, &1.name}))
  end

  @doc "A complex type's attributes, base types first, with groups and references expanded."
  @spec attributes(Schema.t(), ComplexType.t()) :: [AttributeDecl.t()]
  def attributes(schema, %ComplexType{} = type), do: collect_attributes(schema, type, MapSet.new())

  defp collect_attributes(schema, %ComplexType{} = type, seen) do
    key = {type.ns, type.name}

    if type.name != nil and MapSet.member?(seen, key) do
      []
    else
      seen = MapSet.put(seen, key)

      inherited =
        case resolve(schema, type.base) do
          %ComplexType{} = parent -> collect_attributes(schema, parent, seen)
          _ -> []
        end

      inherited ++ expand_attributes(schema, type.attributes, seen)
    end
  end

  defp expand_attributes(schema, attributes, seen) do
    Enum.flat_map(attributes, fn
      %AttributeGroupRef{ref: ref} ->
        if MapSet.member?(seen, {:attribute_group, ref}) do
          []
        else
          expand_attributes(
            schema,
            Map.get(schema.attribute_groups, ref, []),
            MapSet.put(seen, {:attribute_group, ref})
          )
        end

      %AttributeDecl{} = attribute ->
        [attribute]
    end)
  end

  @doc """
  Reduces a type to what its text looks like: `{:atomic, builtin_name, simple_type}`,
  `{:list, item}`, `:union`, `:complex`, or `:unknown`.
  """
  def simple_form(schema, type), do: simple_form(schema, type, MapSet.new())

  defp simple_form(_schema, nil, _seen), do: :unknown
  defp simple_form(_schema, {:builtin, name}, _seen), do: {:atomic, name, nil}
  defp simple_form(schema, %ComplexType{simple_content: true, base: base}, seen), do: simple_base(schema, base, seen)
  defp simple_form(_schema, %ComplexType{}, _seen), do: :complex

  defp simple_form(schema, %SimpleType{variety: :list} = type, seen) do
    item = type.inline_item || resolve(schema, type.item_type)
    {:list, simple_form(schema, item, seen)}
  end

  defp simple_form(_schema, %SimpleType{variety: :union}, _seen), do: :union

  defp simple_form(schema, %SimpleType{} = type, seen) do
    key = {type.ns, type.name}

    if type.name != nil and MapSet.member?(seen, key) do
      :unknown
    else
      base = type.inline_item || resolve(schema, type.base)

      case simple_form(schema, base, MapSet.put(seen, key)) do
        {:atomic, name, inherited} -> {:atomic, name, merge_restrictions(type, inherited)}
        other -> other
      end
    end
  end

  defp simple_base(schema, base, seen), do: simple_form(schema, resolve(schema, base), seen)

  # The narrowest enumeration wins.
  defp merge_restrictions(%SimpleType{enumeration: []}, inherited), do: inherited
  defp merge_restrictions(type, _inherited), do: type
end
