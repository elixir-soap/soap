defmodule Soap.Decoder do
  @moduledoc """
  Turns a SOAP reply into plain Elixir data.

  ## The result

  The result is a map of the SOAP Body's children, by local name:

      %{"AddResponse" => %{"AddResult" => 5}}

  Keys are always strings, so a reply can't create atoms. Namespace prefixes are dropped,
  so a server changing its prefix changes nothing. Where a schema is available:

    * An element that can repeat is always a list, even with one item.
    * Values take their schema type: integers, floats, booleans, `Date`, `DateTime`,
      `NaiveDateTime`, `Time`, and `Decimal` when that library is installed. Base64 and
      hex decode to bytes. A value that doesn't parse stays a string.
    * `xsi:nil` is `nil`.

  Attributes appear as `"@name"`, and an element's text next to attributes as `"#text"`.
  This is the same form `Soap.Encoder` accepts. When `xsi:type` says a value is a subtype
  of its declared type, `"@xsi:type"` holds that subtype's local name, which is also how
  `Soap.Encoder` takes it.

  With no schema, an element repeated in the reply is a list and a single one isn't, and
  all values are strings.

  ## Errors

  A SOAP Fault is `{:error, %Soap.Fault{}}`, at any HTTP status. Anything else that isn't
  a usable reply is `{:error, %Soap.Error{}}`.
  """

  alias Soap.{Attachment, Error, Fault, Multipart, Schema, XML}
  alias Soap.Schema.{ComplexType, Walk}
  alias Soap.Service
  alias Soap.Service.{Message, Operation}
  alias Soap.XML.Element

  @env11 "http://schemas.xmlsoap.org/soap/envelope/"
  @env12 "http://www.w3.org/2003/05/soap-envelope"
  @xsi "http://www.w3.org/2001/XMLSchema-instance"
  @xop "http://www.w3.org/2004/08/xop/include"
  @enc11 "http://schemas.xmlsoap.org/soap/encoding/"
  @enc12 "http://www.w3.org/2003/05/soap-encoding"

  @integers ~w(int integer long short byte unsignedInt unsignedLong unsignedShort unsignedByte
               positiveInteger negativeInteger nonPositiveInteger nonNegativeInteger)

  defmodule Decoded do
    @moduledoc "Everything in a decoded reply."
    defstruct [:result, soap_headers: %{}, attachments: []]
    @type t :: %__MODULE__{result: term(), soap_headers: map(), attachments: [Soap.Attachment.t()]}
  end

  @doc """
  Decodes an HTTP response.

  `service` and `operation` can be nil. Replies then decode without a schema.
  """
  @spec decode(Service.t() | nil, Operation.t() | nil, pos_integer(), list(), binary()) ::
          {:ok, Decoded.t()} | {:error, Fault.t() | Error.t()}
  def decode(service, operation, status, headers, body) do
    with {:ok, plain} <- decompress(headers, body),
         {:ok, xml, attachments} <- split_parts(headers, plain) do
      decode_xml(xml, attachments, service, operation, status)
    end
  end

  # Transfer

  defp decompress(headers, body) do
    case header(headers, "content-encoding") do
      "gzip" -> attempt(fn -> :zlib.gunzip(body) end)
      "x-gzip" -> attempt(fn -> :zlib.gunzip(body) end)
      "deflate" -> attempt(fn -> :zlib.uncompress(body) end)
      _ -> {:ok, body}
    end
  end

  defp attempt(fun) do
    {:ok, fun.()}
  rescue
    _ -> {:error, %Error{reason: :invalid_compressed_body}}
  end

  defp split_parts(headers, body) do
    case Multipart.parse(raw_header(headers, "content-type"), body) do
      :not_multipart -> {:ok, body, []}
      {:ok, root, attachments} -> {:ok, root, attachments}
      {:error, reason} -> {:error, %Error{reason: reason}}
    end
  end

  defp header(headers, name) do
    case raw_header(headers, name) do
      nil -> nil
      value -> String.downcase(value)
    end
  end

  defp raw_header(headers, name) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(to_string(key)) == name, do: to_string(value)
    end)
  end

  # Envelope

  defp decode_xml(xml, attachments, service, operation, status) do
    case String.trim(xml) do
      "" -> empty_reply(status, xml)
      _ -> parse_reply(xml, attachments, service, operation, status)
    end
  end

  defp empty_reply(status, _body) when status in 200..299, do: {:ok, %Decoded{result: nil}}
  defp empty_reply(status, body), do: {:error, %Error{reason: {:http_status, status, body}}}

  defp parse_reply(xml, attachments, service, operation, status) do
    case XML.parse(xml) do
      {:ok, %Element{name: "Envelope", ns: ns} = envelope} when ns in [@env11, @env12] ->
        read_envelope(envelope, xml, attachments, service, operation, status)

      {:ok, _other} when status in 200..299 ->
        {:error, %Error{reason: :no_envelope}}

      {:error, reason} when status in 200..299 ->
        {:error, %Error{reason: reason}}

      _not_soap ->
        {:error, %Error{reason: {:http_status, status, xml}}}
    end
  end

  defp read_envelope(%Element{ns: ns} = envelope, xml, attachments, service, operation, status) do
    body = Element.child(envelope, ns, "Body")
    children = if body, do: body.children, else: []
    ctx = context(service, envelope, children, attachments)

    case Enum.find(children, &(&1.name == "Fault" and &1.ns == ns)) do
      nil -> read_result(envelope, xml, children, operation, status, ctx)
      fault -> {:error, read_fault(fault, ns, status, ctx)}
    end
  end

  defp context(service, envelope, children, attachments) do
    %{
      schema: if(service, do: service.schema),
      references: reference_index(children, %{}),
      attachments: attachments,
      envelope_ns: envelope.ns
    }
  end

  defp read_result(_envelope, xml, _children, _operation, status, _ctx) when status not in 200..299 do
    {:error, %Error{reason: {:http_status, status, xml}}}
  end

  defp read_result(envelope, _xml, children, operation, _status, ctx) do
    roots = Enum.reject(children, &multi_ref?/1)

    {:ok,
     %Decoded{
       result: decode_roots(roots, operation, ctx),
       soap_headers: decode_soap_headers(envelope, ctx),
       attachments: ctx.attachments
     }}
  end

  defp decode_roots([], _operation, _ctx), do: nil

  defp decode_roots(roots, operation, ctx) do
    roots
    |> Enum.map(&{&1.name, decode_root(&1, operation, ctx)})
    |> collect()
  end

  defp decode_soap_headers(%Element{ns: ns} = envelope, ctx) do
    case Element.child(envelope, ns, "Header") do
      nil -> %{}
      header -> header.children |> Enum.map(&{&1.name, decode_element(&1, nil, ctx, %{})}) |> collect()
    end
  end

  # rpc/encoded replies can move values out to siblings of the result and link to them.
  defp multi_ref?(%Element{} = element) do
    element.name == "multiRef" or
      Element.attr_ns(element, @enc11, "root") == "0" or
      Element.attr_ns(element, @enc12, "root") == "false"
  end

  # A link can point anywhere in the Body. PHP, for one, puts the target on the first use
  # of a shared value and links to it from the others.
  defp reference_index(children, index) do
    Enum.reduce(children, index, fn child, acc ->
      acc =
        case Element.attr(child, "id") do
          nil -> acc
          id -> Map.put_new(acc, id, child)
        end

      reference_index(child.children, acc)
    end)
  end

  # Faults

  defp read_fault(fault, @env12, status, ctx) do
    code = Element.child(fault, @env12, "Code")
    reason = Element.child(fault, @env12, "Reason")
    role = Element.child(fault, @env12, "Role") || Element.child(fault, @env12, "Node")

    %Fault{
      code: code && code_value(code),
      subcodes: subcodes(code),
      message: reason && reason |> Element.child(@env12, "Text") |> text_of(),
      actor: role && text_of(role),
      detail: fault |> Element.child(@env12, "Detail") |> decode_detail(ctx),
      status: status
    }
  end

  defp read_fault(fault, _ns, status, ctx) do
    child = fn name -> Enum.find(fault.children, &(&1.name == name)) end

    %Fault{
      code: text_of(child.("faultcode")),
      message: text_of(child.("faultstring")),
      actor: text_of(child.("faultactor")),
      detail: decode_detail(child.("detail"), ctx),
      status: status
    }
  end

  defp code_value(code), do: code |> Element.child(@env12, "Value") |> text_of()

  defp subcodes(nil), do: []

  defp subcodes(code) do
    case Element.child(code, @env12, "Subcode") do
      nil -> []
      subcode -> [code_value(subcode) | subcodes(subcode)]
    end
  end

  defp text_of(nil), do: nil
  defp text_of(%Element{text: text}), do: text

  defp decode_detail(nil, _ctx), do: nil
  defp decode_detail(%Element{children: []} = detail, _ctx), do: blank_to_nil(detail.text)

  defp decode_detail(%Element{children: children}, ctx) do
    children |> Enum.map(&{&1.name, decode_element(&1, nil, ctx, %{})}) |> collect()
  end

  defp blank_to_nil(text), do: if(String.trim(text) == "", do: nil, else: text)

  # Elements

  defp decode_root(element, operation, ctx) do
    decode_element(element, root_type(element, operation, ctx), ctx, %{})
  end

  defp root_type(_element, _operation, %{schema: nil}), do: nil

  defp root_type(element, operation, ctx) do
    case output_shape(operation) do
      {:element, qname} -> type_of_global(ctx, qname) || global_type(element, ctx)
      {:rpc, parts} -> {:parts, parts}
      nil -> global_type(element, ctx)
    end
  end

  defp output_shape(%Operation{style: :rpc, output: %Message{parts: parts}}), do: {:rpc, parts}
  defp output_shape(%Operation{output: %Message{body: {:element, qname}}}), do: {:element, qname}
  defp output_shape(_operation), do: nil

  defp type_of_global(ctx, qname) do
    case Walk.find_element(ctx.schema, qname) do
      nil -> nil
      decl -> Walk.type_of(ctx.schema, decl)
    end
  end

  defp global_type(%Element{ns: ns, name: name}, ctx), do: type_of_global(ctx, {ns, name})

  defp decode_element(%Element{} = element, type, ctx, seen) do
    case follow_reference(element, ctx, seen) do
      {:ok, target, seen} -> decode_element(target, type, ctx, seen)
      :cycle -> nil
      :none -> decode_in_place(element, type, ctx, seen)
    end
  end

  defp follow_reference(element, ctx, seen) do
    case Element.attr(element, "href") do
      "#" <> id -> reference_target(id, ctx, seen)
      _ -> soap12_reference(element, ctx, seen)
    end
  end

  defp soap12_reference(element, ctx, seen) do
    case Element.attr_ns(element, @enc12, "ref") do
      nil -> :none
      id -> reference_target(id, ctx, seen)
    end
  end

  defp reference_target(id, ctx, seen) do
    cond do
      Map.has_key?(seen, id) -> :cycle
      Map.has_key?(ctx.references, id) -> {:ok, Map.fetch!(ctx.references, id), Map.put(seen, id, true)}
      true -> :none
    end
  end

  defp decode_in_place(element, type, ctx, seen) do
    cond do
      Element.attr_ns(element, @xsi, "nil") in ["true", "1"] -> nil
      include = Element.child(element, @xop, "Include") -> resolve_include(include, ctx)
      true -> decode_typed(element, type, ctx, seen)
    end
  end

  defp decode_typed(element, declared, ctx, seen) do
    effective = effective_type(element, declared, ctx)
    element |> decode_value(effective, ctx, seen) |> add_type_name(element, declared, effective)
  end

  # A subtype is worth reporting. Encoded services label every value, which isn't.
  defp add_type_name(%{} = result, element, %ComplexType{} = declared, effective)
       when not is_struct(result) and effective != declared do
    Map.put(result, "@xsi:type", element |> Element.attr_ns(@xsi, "type") |> String.split(":") |> List.last())
  end

  defp add_type_name(result, _element, _declared, _effective), do: result

  defp resolve_include(include, ctx) do
    id = include |> Element.attr("href", "") |> String.replace_prefix("cid:", "") |> URI.decode()

    case Enum.find(ctx.attachments, &(&1.id == id)) do
      %Attachment{data: data} -> data
      nil -> nil
    end
  end

  # xsi:type says which subtype this value really is.
  defp effective_type(element, type, %{schema: nil}), do: xsi_builtin(element) || type

  defp effective_type(element, type, ctx) do
    case Element.attr_ns(element, @xsi, "type") do
      nil -> type
      value -> Walk.resolve(ctx.schema, Element.qname(element, value)) || type
    end
  end

  # Even with no WSDL, a value can say that it's a number or a boolean.
  defp xsi_builtin(element) do
    with value when not is_nil(value) <- Element.attr_ns(element, @xsi, "type"),
         {_ns, local} = qname <- Element.qname(element, value),
         true <- Schema.builtin?(qname) do
      {:builtin, local}
    else
      _ -> nil
    end
  end

  defp decode_value(%Element{children: []} = element, type, ctx, _seen) do
    attrs = attributes(element, type, ctx)
    value = decode_text(element.text, type, ctx)

    cond do
      map_size(attrs) == 0 -> value
      value in [nil, %{}] -> attrs
      true -> Map.put(attrs, "#text", value)
    end
  end

  defp decode_value(%Element{} = element, {:parts, parts}, ctx, seen) do
    element.children
    |> Enum.map(fn child -> {child.name, decode_element(child, part_type(parts, child, ctx), ctx, seen)} end)
    |> collect()
  end

  defp decode_value(%Element{} = element, %ComplexType{array_type: item}, ctx, seen) when not is_nil(item) do
    item_type = Walk.resolve(ctx.schema, item)
    Enum.map(element.children, &decode_element(&1, item_type, ctx, seen))
  end

  defp decode_value(%Element{} = element, %ComplexType{} = type, ctx, seen) do
    if soap_array?(element), do: decode_array(element, ctx, seen), else: decode_fields(element, type, ctx, seen)
  end

  defp decode_value(%Element{} = element, _type, ctx, seen) do
    if soap_array?(element) do
      decode_array(element, ctx, seen)
    else
      element.children
      |> Enum.map(&{&1.name, decode_element(&1, nil, ctx, seen)})
      |> collect()
      |> Map.merge(attributes(element, nil, ctx))
      |> add_mixed_text(element, nil)
    end
  end

  defp decode_array(element, ctx, seen), do: Enum.map(element.children, &decode_element(&1, nil, ctx, seen))

  defp decode_fields(element, type, ctx, seen) do
    {fields, _open?} = Walk.fields(ctx.schema, type)

    element.children
    |> Enum.map(fn child ->
      field = find_field(fields, child, ctx)
      {child.name, decode_element(child, field_type(field, child, ctx), ctx, seen), field != nil and field.repeats}
    end)
    |> collect_with_shape(fields)
    |> Map.merge(attributes(element, type, ctx))
    |> add_mixed_text(element, type)
  end

  # With no schema, a soapenc:Array still says that it's one.
  defp soap_array?(element) do
    Element.attr_ns(element, @enc11, "arrayType") != nil or Element.attr_ns(element, @enc12, "itemType") != nil
  end

  defp part_type(parts, child, ctx) do
    case Enum.find(parts, &(&1.name == child.name)) do
      %{type: type} when not is_nil(type) -> Walk.resolve(ctx.schema, type)
      %{element: element} when not is_nil(element) -> type_of_global(ctx, element)
      _ -> nil
    end
  end

  defp find_field(fields, child, ctx) do
    Enum.find(fields, &(&1.name == child.name)) || find_substituted(fields, child, ctx)
  end

  defp find_substituted(fields, child, ctx) do
    Enum.find(fields, fn field ->
      head = field.global_ref || {field.ns, field.name}
      field.abstract and Enum.any?(Walk.substitutes(ctx.schema, head), &(&1.name == child.name))
    end)
  end

  defp field_type(nil, child, ctx), do: global_type(child, ctx)

  defp field_type(field, child, ctx) do
    if field.name == child.name, do: Walk.type_of(ctx.schema, field), else: global_type(child, ctx)
  end

  defp add_mixed_text(result, %Element{} = element, type) do
    mixed? = match?(%ComplexType{mixed: true}, type) or type == nil
    if mixed? and String.trim(element.text) != "", do: Map.put(result, "#text", element.text), else: result
  end

  # Repeats a key into a list, and gives repeating fields a list even with one value.
  defp collect_with_shape(triples, fields) do
    from_reply =
      triples
      |> Enum.reduce(%{}, fn {name, value, repeats?}, acc ->
        add(acc, name, value, repeats?)
      end)

    Enum.reduce(fields, reverse_lists(from_reply), fn field, acc ->
      # A repeating element that isn't present stays absent, so absent and empty differ.
      if field.repeats and is_map_key(acc, field.name) and not is_list(acc[field.name]) do
        Map.put(acc, field.name, [acc[field.name]])
      else
        acc
      end
    end)
  end

  defp collect(pairs) do
    pairs
    |> Enum.reduce(%{}, fn {name, value}, acc -> add(acc, name, value, false) end)
    |> reverse_lists()
  end

  defp add(acc, name, value, repeats?) do
    case acc do
      %{^name => {:many, values}} -> Map.put(acc, name, {:many, [value | values]})
      %{^name => existing} -> Map.put(acc, name, {:many, [value, existing]})
      _ when repeats? -> Map.put(acc, name, {:many, [value]})
      _ -> Map.put(acc, name, value)
    end
  end

  defp reverse_lists(map) do
    Map.new(map, fn
      {name, {:many, values}} -> {name, Enum.reverse(values)}
      pair -> pair
    end)
  end

  defp attributes(element, type, ctx) do
    declared = declared_attribute_types(type, ctx)

    for {{ns, name}, value} <- element.attrs,
        ns not in [@xsi, @enc11, @enc12, @env11, @env12],
        name not in ["href", "id"],
        into: %{} do
      {"@" <> name, decode_attribute(value, name, declared, ctx)}
    end
  end

  defp declared_attribute_types(%ComplexType{} = type, %{schema: %Schema{} = schema}), do: Walk.attributes(schema, type)
  defp declared_attribute_types(_type, _ctx), do: []

  defp decode_attribute(value, name, declared, ctx) do
    case Enum.find(declared, &(&1.name == name)) do
      nil -> value
      decl -> decode_text(value, decl.inline || Walk.resolve(ctx.schema, decl.type), ctx)
    end
  end

  # Text

  defp decode_text(text, nil, _ctx), do: if(String.trim(text) == "", do: nil, else: text)
  defp decode_text(text, {:parts, _}, _ctx), do: blank_to_nil(text)

  defp decode_text(text, {:builtin, name}, _ctx), do: convert(name, text)

  defp decode_text(text, type, %{schema: %Schema{} = schema}) do
    case Walk.simple_form(schema, type) do
      {:atomic, name, _} -> convert(name, text)
      {:list, {:atomic, name, _}} -> text |> String.split() |> Enum.map(&convert(name, &1))
      :complex -> blank_to_nil(text) || %{}
      _ -> text
    end
  end

  defp decode_text(text, _type, _ctx), do: blank_to_nil(text)

  defp convert(name, text) when name in @integers do
    case Integer.parse(String.trim(text)) do
      {number, ""} -> number
      _ -> text
    end
  end

  defp convert(name, text) when name in ["double", "float"], do: convert_float(String.trim(text), text)

  defp convert("decimal", text), do: convert_decimal(String.trim(text), text)

  defp convert("boolean", text) do
    case String.trim(text) do
      value when value in ["true", "1"] -> true
      value when value in ["false", "0"] -> false
      _ -> text
    end
  end

  defp convert("date", text), do: keep_on_error(Date.from_iso8601(String.trim(text)), text)
  defp convert("time", text), do: keep_on_error(Time.from_iso8601(String.trim(text)), text)

  defp convert("dateTime", text) do
    trimmed = String.trim(text)

    case DateTime.from_iso8601(trimmed) do
      {:ok, value, _offset} -> value
      _ -> keep_on_error(NaiveDateTime.from_iso8601(trimmed), text)
    end
  end

  defp convert("base64Binary", text), do: text |> String.replace(~r/\s/, "") |> Base.decode64() |> keep_bytes(text)
  defp convert("hexBinary", text), do: text |> String.trim() |> Base.decode16(case: :mixed) |> keep_bytes(text)
  defp convert(_name, text), do: text

  defp convert_float("INF", _text), do: :infinity
  defp convert_float("+INF", _text), do: :infinity
  defp convert_float("-INF", _text), do: :negative_infinity
  defp convert_float("NaN", _text), do: :nan

  defp convert_float(trimmed, text) do
    case Float.parse(trimmed) do
      {number, ""} -> number
      _ -> text
    end
  end

  defp convert_decimal(trimmed, text) do
    if Code.ensure_loaded?(Decimal) do
      case Decimal.parse(trimmed) do
        {decimal, ""} -> decimal
        _ -> text
      end
    else
      text
    end
  end

  defp keep_on_error({:ok, value}, _text), do: value
  defp keep_on_error(_error, text), do: text

  defp keep_bytes({:ok, bytes}, _text), do: bytes
  defp keep_bytes(:error, text), do: text
end
