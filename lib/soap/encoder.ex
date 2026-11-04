defmodule Soap.Encoder do
  @moduledoc """
  Builds the XML for a request, using the schema to order and qualify its elements.

  ## Params

  Params can be a map, a keyword list, or a list of `{name, value}` or
  `{name, attributes, value}` tuples. Names can be atoms or strings, and a prefix on a
  name is ignored. To name an element outside the schema, use a `{namespace, name}` key.

      %{"Customer" => %{"Name" => "Ann", "Phones" => ["1", "2"]}}

  In a map, keys starting with `@` are attributes and `#text` is an element's text. This
  is the same form responses decode to.

      %{"Price" => %{"@currency" => "EUR", "#text" => 10}}

  A list value repeats the element. `nil` omits the element, or sends `xsi:nil` when the
  schema says it's nillable. `%Soap.Raw{}` is sent as is, and `%Soap.Attachment{}` is sent
  by MTOM.

  Values go out in the form their schema type needs. Base64 and hex fields take the raw
  bytes and encode them.

  ## Validation

  A value that can't fit its type, or an element the schema doesn't allow, is an error,
  and nothing gets sent. `validate: false` turns this off. Missing required elements are
  allowed, because servers often accept less than their WSDL says.
  """

  alias Soap.{Attachment, Error, Raw, Schema}
  alias Soap.Schema.{ComplexType, SimpleType, Walk}
  alias Soap.Service
  alias Soap.Service.{Message, Operation}

  @envelope_ns %{
    "1.1" => "http://schemas.xmlsoap.org/soap/envelope/",
    "1.2" => "http://www.w3.org/2003/05/soap-envelope"
  }
  @encoding_ns "http://schemas.xmlsoap.org/soap/encoding/"
  @xsi "http://www.w3.org/2001/XMLSchema-instance"
  @xsd "http://www.w3.org/2001/XMLSchema"
  @xop "http://www.w3.org/2004/08/xop/include"
  @fixed_prefixes %{
    @xsi => "xsi",
    @xsd => "xsd",
    @encoding_ns => "soapenc",
    @xop => "xop",
    "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" => "wsse",
    "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" => "wsu"
  }

  @integers ~w(int integer long short byte unsignedInt unsignedLong unsignedShort unsignedByte
               positiveInteger negativeInteger nonPositiveInteger nonNegativeInteger)

  @doc """
  Encodes one operation's request.

  Returns the XML and any attachments it refers to.

  ## Options

    * `:headers` - SOAP headers, in the same forms as params.
    * `:mtom` - send every base64 field as an attachment.
    * `:validate` - check params against the schema. Defaults to true.
  """
  @spec encode(Service.t(), Operation.t(), term(), keyword()) ::
          {:ok, %{xml: binary(), attachments: [Attachment.t()]}} | {:error, Error.t()}
  def encode(%Service{} = service, %Operation{} = operation, params, opts \\ []) do
    ctx = %{
      schema: service.schema,
      validate: Keyword.get(opts, :validate, true),
      mtom: Keyword.get(opts, :mtom, false),
      encoded: match?(%Message{use: :encoded}, operation.input),
      envelope_ns: Map.fetch!(@envelope_ns, operation.version)
    }

    body = encode_body(operation, params, ctx)
    header = encode_headers(operation, Keyword.get(opts, :headers, []), ctx)
    {:ok, serialize(envelope(header, body, ctx))}
  catch
    {:invalid_param, path, message} ->
      {:error, %Error{reason: {:invalid_param, Enum.join(Enum.reverse(path), "/"), message}}}
  end

  defp envelope(header, body, ctx) do
    header_node = if header == [], do: [], else: [{{ctx.envelope_ns, "Header"}, [], header}]
    {{ctx.envelope_ns, "Envelope"}, [], header_node ++ [{{ctx.envelope_ns, "Body"}, [], body}]}
  end

  # Body

  defp encode_body(%Operation{input: nil}, _params, _ctx), do: []

  defp encode_body(%Operation{input: %Message{body: {:element, qname}}}, params, ctx) do
    [encode_global_element(qname, params, ctx)]
  end

  defp encode_body(%Operation{input: %Message{body: {:rpc, qname}} = input}, params, ctx) do
    attrs = encoding_attrs(input, ctx)
    [{qname, attrs, encode_parts(input.parts, params, [elem(qname, 1)], ctx)}]
  end

  defp encode_body(%Operation{input: %Message{body: :parts} = input}, params, ctx) do
    encode_parts(input.parts, params, [], ctx)
  end

  defp encode_body(%Operation{input: %Message{body: :empty}}, _params, _ctx), do: []

  defp encoding_attrs(%Message{use: :encoded} = input, ctx) do
    [{{ctx.envelope_ns, "encodingStyle"}, input.encoding_style || @encoding_ns}]
  end

  defp encoding_attrs(_input, _ctx), do: []

  defp encode_global_element({_ns, local} = qname, params, ctx) do
    decl = Walk.find_element(ctx.schema, qname)
    type = decl && Walk.type_of(ctx.schema, decl)
    {attrs, value} = split_wrapper_value(params)
    encode_value(declared_qname(decl, qname), attrs, value, type, %{nillable: false}, [local], ctx)
  end

  # The schema knows an element's real namespace, even if a WSDL's reference to it is sloppy.
  defp declared_qname(nil, qname), do: qname
  defp declared_qname(decl, _qname), do: {decl.ns, decl.name}

  defp split_wrapper_value({_name, attrs, value}) when is_map(attrs), do: {attrs, value}
  defp split_wrapper_value(params), do: {%{}, params}

  defp encode_parts(parts, params, path, ctx) do
    entries = entries(params)

    {nodes, rest} =
      Enum.flat_map_reduce(parts, entries, fn part, remaining ->
        {matching, others} = Enum.split_with(remaining, &(local_name(&1) == part.name or part_element?(part, &1)))
        {Enum.flat_map(matching, &encode_part(part, &1, path, ctx)), others}
      end)

    check_unknown(rest, path, ctx, Enum.map(parts, & &1.name))
    nodes ++ Enum.flat_map(rest, &schemaless_entry(&1, {nil, nil}, path, ctx))
  end

  defp part_element?(%{element: {_ns, local}}, entry), do: local_name(entry) == local
  defp part_element?(_part, _entry), do: false

  defp encode_part(%{element: {_, local} = qname}, {_key, attrs, value}, path, ctx) do
    decl = Walk.find_element(ctx.schema, qname)
    type = decl && Walk.type_of(ctx.schema, decl)
    [encode_value(declared_qname(decl, qname), attrs, value, type, %{nillable: false}, [local | path], ctx)]
  end

  defp encode_part(part, {_key, attrs, value}, path, ctx) do
    type = Walk.resolve(ctx.schema, part.type)
    field = %{nillable: false, type: part.type}
    encode_repeated({nil, part.name}, attrs, value, type, field, [part.name | path], ctx)
  end

  # Headers

  defp encode_headers(%Operation{input: input}, headers, ctx) do
    declared = if input, do: input.headers, else: []

    headers
    |> entries()
    |> Enum.map(fn entry -> encode_header(entry, declared, ctx) end)
  end

  defp encode_header({%Raw{} = raw, _attrs, _value}, _declared, _ctx), do: raw

  defp encode_header({key, attrs, value} = entry, declared, ctx) do
    name = local_name(entry)

    case Enum.find(declared, &header_matches?(&1, name)) do
      %{element: {_, _} = qname} ->
        decl = Walk.find_element(ctx.schema, qname)
        encode_value(qname, attrs, value, decl && Walk.type_of(ctx.schema, decl), %{nillable: false}, [name], ctx)

      %{type: {_, _} = type_name, namespace: namespace} ->
        field = %{nillable: false, type: type_name}
        encode_value({namespace, name}, attrs, value, Walk.resolve(ctx.schema, type_name), field, [name], ctx)

      _ ->
        encode_value(explicit_qname(key, name), attrs, value, nil, %{nillable: false}, [name], ctx)
    end
  end

  defp header_matches?(%{name: name}, wanted) when name == wanted, do: true
  defp header_matches?(%{element: {_, local}}, wanted), do: local == wanted
  defp header_matches?(_header, _wanted), do: false

  defp explicit_qname({ns, name}, _local) when is_binary(name), do: {ns, name}
  defp explicit_qname(_key, local), do: {nil, local}

  # Elements

  defp encode_repeated(qname, attrs, values, type, field, path, ctx) when is_list(values) do
    if plain_list?(values) and not list_type?(type, ctx) do
      Enum.map(values, &encode_value(qname, attrs, &1, type, field, path, ctx))
    else
      [encode_value(qname, attrs, values, type, field, path, ctx)]
    end
  end

  defp encode_repeated(qname, attrs, value, type, field, path, ctx) do
    [encode_value(qname, attrs, value, type, field, path, ctx)]
  end

  # A list of scalars or maps repeats the element. A list of tuples is one element's content.
  defp plain_list?([]), do: false
  defp plain_list?(values), do: not Enum.all?(values, &is_tuple/1)

  defp list_type?(nil, _ctx), do: false
  defp list_type?(%ComplexType{array_type: item}, _ctx) when not is_nil(item), do: true
  defp list_type?(type, ctx), do: match?({:list, _}, Walk.simple_form(ctx.schema, type))

  defp encode_value(qname, attrs, nil, _type, %{nillable: true}, _path, _ctx) do
    {qname, [{{@xsi, "nil"}, "true"} | plain_attrs(attrs)], []}
  end

  defp encode_value(qname, attrs, %Raw{} = raw, _type, _field, _path, _ctx) do
    {qname, plain_attrs(attrs), raw}
  end

  defp encode_value(qname, attrs, %Attachment{} = attachment, _type, _field, _path, _ctx) do
    {qname, plain_attrs(attrs), attachment}
  end

  defp encode_value(qname, attrs, value, type, field, path, ctx) do
    {more_attrs, value} = split_special_keys(value)
    attrs = Map.merge(to_string_map(attrs), more_attrs)
    {type, type_attr} = apply_xsi_type(type, attrs, ctx)
    encoded = if type_attr == [], do: encoded_type_attr(type, field, ctx), else: []
    node_attrs = type_attr ++ encoded ++ node_attributes(attrs, type, path, ctx)

    {children, array_attrs} = encode_content(value, qname, type, path, ctx)
    {qname, array_attrs ++ node_attrs, children}
  end

  # A type chosen by the caller, for elements whose declared type is a base type.
  defp apply_xsi_type(type, attrs, ctx) do
    case Map.get(attrs, "xsi:type") || Map.get(attrs, "type_override") do
      nil ->
        {type, []}

      {ns, local} ->
        {Walk.find_type(ctx.schema, {ns, local}) || type, [{{@xsi, "type"}, {:qname, {ns, local}}}]}

      name ->
        local = name |> String.split(":") |> List.last()
        found = Walk.find_type(ctx.schema, {nil, local})
        {found || type, [{{@xsi, "type"}, {:qname, {found && found.ns, local}}}]}
    end
  end

  # rpc/encoded tells the reader each value's type.
  defp encoded_type_attr(_type, _field, %{encoded: false}), do: []

  defp encoded_type_attr(type, field, _ctx) do
    case Map.get(field, :type) || type_name(type) do
      nil -> []
      qname -> [{{@xsi, "type"}, {:qname, qname}}]
    end
  end

  defp type_name(%ComplexType{name: name, ns: ns}) when not is_nil(name), do: {ns, name}
  defp type_name(%SimpleType{name: name, ns: ns}) when not is_nil(name), do: {ns, name}
  defp type_name({:builtin, name}), do: {@xsd, name}
  defp type_name(_type), do: nil

  defp plain_attrs(attrs), do: attrs |> to_string_map() |> Enum.map(fn {k, v} -> {{nil, k}, to_string(v)} end)

  defp node_attributes(attrs, type, path, ctx) do
    declared = declared_attributes(type, ctx)

    attrs
    |> Enum.reject(fn {name, _} -> name in ["xsi:type", "type_override"] or namespace_declaration?(name) end)
    |> Enum.map(fn {name, value} ->
      local = name |> String.split(":") |> List.last()

      case Enum.find(declared, &(&1.name == local)) do
        nil -> {{nil, name}, attribute_text(value)}
        decl -> {{decl.ns, local}, format_attribute(decl, value, ["@" <> local | path], ctx)}
      end
    end)
  end

  defp namespace_declaration?(name), do: name == "xmlns" or String.starts_with?(name, "xmlns:")

  defp declared_attributes(%ComplexType{} = type, ctx), do: Walk.attributes(ctx.schema, type)
  defp declared_attributes(_type, _ctx), do: []

  defp attribute_text(value) when is_binary(value), do: value
  defp attribute_text(value), do: to_string(value)

  defp format_attribute(decl, value, path, ctx) do
    type = decl.inline || Walk.resolve(ctx.schema, decl.type)
    format_scalar(value, type, path, ctx)
  end

  defp encode_content(value, qname, %ComplexType{array_type: item} = type, path, ctx)
       when not is_nil(item) and is_list(value) do
    encode_array(value, qname, type, path, ctx)
  end

  defp encode_content(value, qname, %ComplexType{simple_content: false} = type, path, ctx) do
    {encode_complex(value, qname, type, path, ctx), []}
  end

  defp encode_content(value, _qname, %ComplexType{simple_content: true} = type, path, ctx) do
    text = Walk.resolve(ctx.schema, type.base)
    {scalar_content(text_of(value), text, path, ctx), []}
  end

  defp encode_content(value, qname, nil, path, ctx), do: {encode_schemaless(value, qname, path, ctx), []}

  defp encode_content(value, qname, type, path, ctx) do
    case Walk.simple_form(ctx.schema, type) do
      form when form in [:unknown, :complex] -> {encode_schemaless(value, qname, path, ctx), []}
      {:atomic, "anyType", _} -> {encode_schemaless(value, qname, path, ctx), []}
      _ -> {scalar_content(text_of(value), type, path, ctx), []}
    end
  end

  defp text_of(%{"#text" => text}), do: text
  defp text_of(value) when is_list(value) and value == [], do: nil
  defp text_of(value), do: value

  defp encode_array(values, qname, type, path, ctx) do
    item_type = Walk.resolve(ctx.schema, type.array_type)
    {ns, local} = type.array_type
    item = %{nillable: false, type: type.array_type}
    item_qname = {elem(qname, 0) && nil, "item"}

    children = Enum.map(values, &encode_value(item_qname, %{}, &1, item_type, item, ["item" | path], ctx))
    {children, [{{@encoding_ns, "arrayType"}, {:qname_suffix, {ns, local}, "[#{length(values)}]"}}]}
  end

  defp encode_complex(value, qname, type, path, ctx) do
    {fields, open?} = Walk.fields(ctx.schema, type)

    case {fields, open?, scalar?(value)} do
      {[], true, _} -> encode_schemaless(value, qname, path, ctx)
      {_, _, true} when value not in [nil, ""] -> invalid(path, "expected elements, got #{inspect(value)}", ctx, value)
      _ -> encode_fields(entries(value), fields, open?, qname, path, ctx)
    end
  end

  # With validation off, a scalar goes into an element the schema says is complex.
  defp invalid(path, message, %{validate: true}, _value), do: throw({:invalid_param, path, message})
  defp invalid(_path, _message, _ctx, value), do: scalar_text(value)

  defp scalar?(value), do: not (is_map(value) or is_list(value) or is_nil(value) or is_tuple(value))

  defp encode_fields(entries, fields, open?, parent, path, ctx) do
    {placed, leftovers} =
      Enum.flat_map_reduce(entries, [], fn entry, rest ->
        case find_field(entry, fields, ctx) do
          nil -> {[], [entry | rest]}
          {field, name_ns} -> {encode_field(entry, field, name_ns, path, ctx), rest}
        end
      end)

    extras = encode_leftovers(Enum.reverse(leftovers), fields, open?, parent, path, ctx)

    placed
    |> Enum.sort_by(fn {order, _node} -> order end)
    |> Enum.map(fn {_order, node} -> node end)
    |> Kernel.++(extras)
  end

  defp find_field(entry, fields, ctx) do
    name = local_name(entry)

    case Enum.find(fields, &(&1.name == name)) do
      nil -> find_substitute(name, fields, ctx)
      field -> {field, nil}
    end
  end

  # A member of a substitution group can stand in for its head element.
  defp find_substitute(name, fields, ctx) do
    Enum.find_value(fields, fn field ->
      head = field.global_ref || {field.ns, field.name}

      case Enum.find(Walk.substitutes(ctx.schema, head), &(&1.name == name)) do
        nil -> nil
        member -> {%{field | name: member.name, ns: member.ns, type: member.type, inline: member.inline}, member.ns}
      end
    end)
  end

  defp encode_field({_key, attrs, value}, field, _ns, path, ctx) do
    type = Walk.type_of(ctx.schema, field)
    child_path = [field.name | path]

    if is_nil(value) and not field.nillable do
      []
    else
      {field.ns, field.name}
      |> encode_repeated(attrs, value, type, field, child_path, ctx)
      |> Enum.map(&{field.order, &1})
    end
  end

  defp encode_leftovers([], _fields, _open?, _parent, _path, _ctx), do: []

  defp encode_leftovers(entries, fields, open?, parent, path, ctx) do
    if open? or not ctx.validate do
      Enum.flat_map(entries, &schemaless_entry(&1, sibling_scope(fields, parent), path, ctx))
    else
      check_unknown(entries, path, ctx, Enum.map(fields, & &1.name))
    end
  end

  # An element the schema doesn't name is qualified the way its siblings are.
  defp sibling_scope([%{ns: ns} | _], {_ns, name}), do: {ns, name}
  defp sibling_scope([], parent), do: parent

  defp check_unknown([], _path, _ctx, _allowed), do: []
  defp check_unknown(_entries, _path, %{validate: false}, _allowed), do: []

  defp check_unknown([entry | _], path, _ctx, allowed) do
    name = local_name(entry)
    throw({:invalid_param, [name | path], "not allowed here. Expected one of: #{Enum.join(allowed, ", ")}"})
  end

  # With no schema to follow, children are qualified if the parent's schema says so, and
  # if it's unknown, they inherit the parent's namespace.
  defp encode_schemaless(value, {ns, _} = qname, path, ctx) do
    scope = if Schema.element_form(ctx.schema, ns) == "unqualified", do: {nil, nil}, else: qname

    cond do
      is_nil(value) -> []
      match?(%Raw{}, value) -> value
      scalar?(value) -> scalar_text(value)
      true -> value |> entries() |> Enum.flat_map(&schemaless_entry(&1, scope, path, ctx))
    end
  end

  defp schemaless_entry({:text, _attrs, text}, _parent, _path, _ctx), do: [scalar_text(text)]

  defp schemaless_entry({key, attrs, value} = entry, {parent_ns, _}, path, ctx) do
    name = local_name(entry)
    qname = if match?({_, _}, key), do: key, else: {parent_ns, name}
    field = %{nillable: false}
    encode_repeated(qname, attrs, value, nil, field, [name | path], ctx)
  end

  # Scalars

  defp scalar_content(nil, _type, _path, _ctx), do: []
  defp scalar_content(%Raw{} = raw, _type, _path, _ctx), do: raw
  defp scalar_content(value, type, path, ctx), do: format_scalar(value, type, path, ctx)

  defp format_scalar(value, type, path, ctx) do
    case Walk.simple_form(ctx.schema, type) do
      {:atomic, "base64Binary", _} when ctx.mtom and is_binary(value) -> %Attachment{data: value}
      {:atomic, name, simple} -> format_atomic(value, name, simple, path, ctx)
      {:list, item} -> format_list(value, item, path, ctx)
      _ -> scalar_text(value)
    end
  end

  defp format_list(values, {:atomic, name, simple}, path, ctx) when is_list(values) do
    Enum.map_join(values, " ", &format_atomic(&1, name, simple, path, ctx))
  end

  defp format_list(value, _item, _path, _ctx), do: scalar_text(value)

  defp format_atomic(value, name, simple, path, ctx) do
    if ctx.validate do
      text = convert(name, value, path)
      check_enumeration(text, simple, path)
      text
    else
      convert_loosely(name, value)
    end
  end

  defp check_enumeration(_text, nil, _path), do: :ok
  defp check_enumeration(_text, %SimpleType{enumeration: []}, _path), do: :ok

  defp check_enumeration(text, %SimpleType{enumeration: allowed}, path) do
    unless text in allowed do
      throw({:invalid_param, path, "#{inspect(text)} isn't one of: #{Enum.join(allowed, ", ")}"})
    end
  end

  defp convert_loosely(name, value) when name in ["base64Binary", "hexBinary"] and is_binary(value) do
    convert(name, value, [])
  end

  defp convert_loosely(_name, value), do: scalar_text(value)

  defp convert(name, value, path) when name in @integers do
    text = scalar_text(value)
    if integer_text?(text), do: text, else: bad(path, value, name)
  end

  defp convert("decimal", value, path) do
    text = scalar_text(value)
    if Regex.match?(~r/^\s*[+-]?(\d+(\.\d*)?|\.\d+)\s*$/, text), do: text, else: bad(path, value, "decimal")
  end

  defp convert(name, value, path) when name in ["double", "float"] do
    text = scalar_text(value)

    if Regex.match?(~r/^\s*([+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?|[+-]?INF|NaN)\s*$/, text) do
      text
    else
      bad(path, value, name)
    end
  end

  defp convert("boolean", value, path) do
    case value do
      v when v in [true, "true", "1", 1] -> "true"
      v when v in [false, "false", "0", 0] -> "false"
      _ -> bad(path, value, "boolean")
    end
  end

  defp convert("date", %Date{} = value, _path), do: Date.to_iso8601(value)

  defp convert("date", value, path) when is_binary(value) do
    if valid_date?(value), do: value, else: bad(path, value, "date")
  end

  defp convert("dateTime", %DateTime{} = value, _path), do: DateTime.to_iso8601(value)
  defp convert("dateTime", %NaiveDateTime{} = value, _path), do: NaiveDateTime.to_iso8601(value)

  defp convert("dateTime", value, path) when is_binary(value) do
    case String.split(value, "T", parts: 2) do
      [date, time] -> if valid_date?(date) and valid_time?(time), do: value, else: bad(path, value, "dateTime")
      _ -> bad(path, value, "dateTime")
    end
  end

  defp convert("time", %Time{} = value, _path), do: Time.to_iso8601(value)

  defp convert("time", value, path) when is_binary(value) do
    if valid_time?(value), do: value, else: bad(path, value, "time")
  end

  defp convert("base64Binary", value, _path) when is_binary(value), do: Base.encode64(value)
  defp convert("hexBinary", value, _path) when is_binary(value), do: Base.encode16(value)

  defp convert(name, value, path) when name in ["date", "dateTime", "time", "base64Binary", "hexBinary"] do
    bad(path, value, name)
  end

  defp convert(_name, value, _path), do: scalar_text(value)

  defp bad(path, value, type), do: throw({:invalid_param, path, "#{inspect(value)} isn't a valid #{type}"})

  defp integer_text?(text), do: Regex.match?(~r/^\s*[+-]?\d+\s*$/, text)

  defp valid_date?(value) do
    case Regex.run(~r/^(\d{4}-\d{2}-\d{2})(Z|[+-]\d{2}:\d{2})?$/, value) do
      [_, date | _] -> match?({:ok, _}, Date.from_iso8601(date))
      nil -> false
    end
  end

  defp valid_time?(value), do: Regex.match?(~r/^([01]\d|2[0-4]):[0-5]\d:[0-6]\d(\.\d+)?(Z|[+-]\d{2}:\d{2})?$/, value)

  defp scalar_text(value) when is_binary(value), do: value
  defp scalar_text(true), do: "true"
  defp scalar_text(false), do: "false"
  defp scalar_text(%{__struct__: _} = value), do: to_string(value)
  defp scalar_text(value) when is_map(value) or is_tuple(value) or is_list(value), do: inspect(value)
  defp scalar_text(value), do: to_string(value)

  # Params

  defp entries(nil), do: []
  defp entries(%Raw{} = raw), do: [{raw, %{}, nil}]
  defp entries(%{__struct__: _}), do: []

  defp entries(map) when is_map(map) do
    {special, plain} = Enum.split_with(map, fn {key, _} -> special_key?(key) end)
    text = for {key, value} <- special, key_text(key) == "#text", do: {:text, %{}, value}
    Enum.flat_map(plain, &entry/1) ++ text
  end

  defp entries(list) when is_list(list), do: Enum.flat_map(list, &entry/1)
  defp entries(_scalar), do: []

  defp entry({name, value}), do: [{name, %{}, value}]
  defp entry({name, attrs, value}) when is_map(attrs), do: [{name, attrs, value}]
  defp entry(%Raw{} = raw), do: [{raw, %{}, nil}]
  defp entry(other), do: throw({:invalid_param, [], "expected a name and value, got #{inspect(other)}"})

  defp special_key?(key), do: String.starts_with?(key_text(key), ["@", "#"])

  defp key_text({_ns, name}), do: to_string(name)
  defp key_text(key), do: to_string(key)

  defp split_special_keys(map) when is_map(map) and not is_struct(map) do
    {special, plain} = Enum.split_with(map, fn {key, _} -> String.starts_with?(key_text(key), "@") end)
    attrs = Map.new(special, fn {key, value} -> {String.trim_leading(key_text(key), "@"), value} end)
    {attrs, Map.new(plain)}
  end

  defp split_special_keys(value), do: {%{}, value}

  defp to_string_map(attrs) when is_map(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  defp to_string_map(nil), do: %{}

  defp local_name({%Raw{}, _attrs, _value}), do: ""
  defp local_name({:text, _attrs, _value}), do: "#text"
  defp local_name({{_ns, name}, _attrs, _value}), do: to_string(name)
  defp local_name({name, _attrs, _value}), do: name |> to_string() |> String.split(":") |> List.last()

  # Serializing

  defp serialize(root) do
    prefixes = collect_prefixes(root, %{})
    {attachments, root} = assign_attachments(root)
    declarations = Enum.map(prefixes, fn {uri, prefix} -> [" xmlns:", prefix, "=\"", escape_attribute(uri), "\""] end)
    xml = [~s(<?xml version="1.0" encoding="UTF-8"?>), write(root, prefixes, declarations)]
    %{xml: IO.iodata_to_binary(xml), attachments: attachments}
  end

  defp collect_prefixes({{ns, _name}, attrs, content}, acc) do
    acc = add_prefix(ns, acc)
    acc = Enum.reduce(attrs, acc, &collect_attribute_prefixes/2)
    collect_content_prefixes(content, acc)
  end

  defp collect_prefixes(_other, acc), do: acc

  defp collect_content_prefixes(%Attachment{}, acc), do: add_prefix(@xop, acc)
  defp collect_content_prefixes(content, acc) when is_list(content), do: Enum.reduce(content, acc, &collect_prefixes/2)
  defp collect_content_prefixes(_content, acc), do: acc

  defp collect_attribute_prefixes({{ns, _name}, value}, acc) do
    acc = add_prefix(ns, acc)

    case value do
      {:qname, {value_ns, _}} -> add_prefix(value_ns, acc)
      {:qname_suffix, {value_ns, _}, _} -> add_prefix(value_ns, acc)
      _ -> acc
    end
  end

  defp add_prefix(nil, acc), do: acc

  defp add_prefix(uri, acc) do
    cond do
      Map.has_key?(acc, uri) -> acc
      uri in [@envelope_ns["1.1"], @envelope_ns["1.2"]] -> Map.put(acc, uri, "env")
      Map.has_key?(@fixed_prefixes, uri) -> Map.put(acc, uri, Map.fetch!(@fixed_prefixes, uri))
      true -> Map.put(acc, uri, "ns#{map_size(acc)}")
    end
  end

  defp assign_attachments(node) do
    {node, {attachments, _count}} = assign(node, {[], 0})
    {Enum.reverse(attachments), node}
  end

  defp assign({qname, attrs, %Attachment{} = attachment}, {list, count}) do
    id = attachment.id || "part#{count + 1}@soap"
    {{qname, attrs, {:xop_include, id}}, {[%{attachment | id: id} | list], count + 1}}
  end

  defp assign({qname, attrs, content}, acc) when is_list(content) do
    {children, acc} = Enum.map_reduce(content, acc, &assign/2)
    {{qname, attrs, children}, acc}
  end

  defp assign(other, acc), do: {other, acc}

  defp write(%Raw{xml: xml}, _prefixes, _declarations), do: xml

  defp write({qname, attrs, content}, prefixes, declarations) do
    tag = tag_name(qname, prefixes)
    attributes = Enum.map(attrs, &write_attribute(&1, prefixes))

    case write_content(content, prefixes) do
      [] -> ["<", tag, declarations, attributes, "/>"]
      "" -> ["<", tag, declarations, attributes, "/>"]
      inner -> ["<", tag, declarations, attributes, ">", inner, "</", tag, ">"]
    end
  end

  defp write(text, _prefixes, _declarations) when is_binary(text), do: text_or_cdata(text)

  defp write_content(%Raw{xml: xml}, _prefixes), do: xml

  defp write_content({:xop_include, id}, prefixes) do
    ["<", Map.fetch!(prefixes, @xop), ":Include href=\"cid:", escape_attribute(id), "\"/>"]
  end

  defp write_content(text, _prefixes) when is_binary(text), do: text_or_cdata(text)
  defp write_content(children, prefixes) when is_list(children), do: Enum.map(children, &write(&1, prefixes, []))

  defp write_attribute({{ns, name}, value}, prefixes) do
    [" ", attribute_name(ns, name, prefixes), "=\"", attribute_value(value, prefixes), "\""]
  end

  defp attribute_name(nil, name, _prefixes), do: name
  defp attribute_name(ns, name, prefixes), do: [Map.fetch!(prefixes, ns), ":", name]

  defp attribute_value({:qname, qname}, prefixes), do: tag_name(qname, prefixes)
  defp attribute_value({:qname_suffix, qname, suffix}, prefixes), do: [tag_name(qname, prefixes), suffix]
  defp attribute_value(value, _prefixes), do: value |> to_string() |> escape_attribute()

  defp tag_name({nil, name}, _prefixes), do: name
  defp tag_name({ns, name}, prefixes), do: [Map.fetch!(prefixes, ns), ":", name]

  # A value that is exactly one CDATA section goes out as that section.
  defp text_or_cdata(<<"<![CDATA[", rest::binary>> = text) do
    if String.ends_with?(rest, "]]>") and :binary.matches(rest, "]]>") |> length() == 1 do
      text
    else
      escape_text(text)
    end
  end

  defp text_or_cdata(text), do: escape_text(text)

  @doc "Escapes text content."
  def escape_text(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\r", "&#13;")
  end

  defp escape_attribute(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("\n", "&#10;")
    |> String.replace("\t", "&#9;")
    |> String.replace("\r", "&#13;")
  end
end
