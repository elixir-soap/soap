defmodule Soap.Service.Reader do
  @moduledoc """
  Builds a `Soap.Service` from loaded WSDL documents.

  References are matched on their full qualified name first and then on the local name
  alone, because real documents often bind a prefix to the wrong namespace.
  """

  alias Soap.Service
  alias Soap.Service.{Header, Message, Operation, Part, Port}
  alias Soap.XML.Element

  @wsdl "http://schemas.xmlsoap.org/wsdl/"
  @soap11 "http://schemas.xmlsoap.org/wsdl/soap/"
  @soap12 "http://schemas.xmlsoap.org/wsdl/soap12/"

  @doc "Reads the output of `Soap.Service.Loader`."
  @spec read(Soap.Service.Loader.result()) :: Service.t()
  def read(%{wsdls: wsdls, schema: schema, unresolved_imports: unresolved}) do
    index = %{
      messages: index(wsdls, "message"),
      port_types: index(wsdls, "portType")
    }

    bindings = Enum.flat_map(wsdls, &soap_bindings/1)

    %Service{
      target_namespace: target_namespace(wsdls),
      operations: Enum.flat_map(bindings, &binding_operations(&1, index)),
      ports: Enum.flat_map(wsdls, &ports(&1, bindings)),
      schema: schema,
      unresolved_imports: unresolved
    }
  end

  defp target_namespace([]), do: nil
  defp target_namespace(wsdls), do: wsdls |> List.last() |> Element.attr("targetNamespace")

  defp wsdl_children(element, name), do: Enum.filter(element.children, &(&1.name == name and &1.ns in [@wsdl, nil]))

  # Declarations of one kind across all documents, keyed by qualified name.
  defp index(wsdls, kind) do
    for wsdl <- wsdls, element <- wsdl_children(wsdl, kind), into: %{} do
      {{Element.attr(wsdl, "targetNamespace"), Element.attr(element, "name")}, element}
    end
  end

  defp lookup(_index, nil), do: nil

  defp lookup(index, {_ns, local} = qname), do: Map.get(index, qname) || find_by_local_name(index, local)

  defp find_by_local_name(index, local) do
    Enum.find_value(index, fn {{_ns, name}, found} -> if name == local, do: found end)
  end

  # Bindings

  defp soap_bindings(wsdl) do
    Enum.flat_map(wsdl_children(wsdl, "binding"), fn binding ->
      case soap_binding_element(binding) do
        nil -> []
        soap -> [%{element: binding, soap: soap, soap_ns: soap.ns, tns: Element.attr(wsdl, "targetNamespace")}]
      end
    end)
  end

  defp soap_binding_element(binding) do
    Enum.find(binding.children, &(&1.name == "binding" and &1.ns in [@soap11, @soap12]))
  end

  defp version(@soap11), do: "1.1"
  defp version(@soap12), do: "1.2"

  defp binding_operations(binding, index) do
    port_type = lookup(index.port_types, Element.qname(binding.element, Element.attr(binding.element, "type")))

    # A binding can name a port type that doesn't exist. Its operations can still be
    # matched by name, which beats sending an empty Body.
    abstract =
      if port_type do
        wsdl_children(port_type, "operation")
      else
        index.port_types |> Map.values() |> Enum.flat_map(&wsdl_children(&1, "operation"))
      end

    binding.element
    |> wsdl_children("operation")
    |> Enum.map(&operation(&1, abstract, binding, index))
  end

  defp operation(element, abstract_operations, binding, index) do
    name = Element.attr(element, "name")
    soap_op = Element.child(element, binding.soap_ns, "operation")
    input = element |> wsdl_children("input") |> List.first()
    output = element |> wsdl_children("output") |> List.first()
    input_name = input && Element.attr(input, "name")
    abstract = find_abstract(abstract_operations, name, input_name)
    style = style(soap_op && Element.attr(soap_op, "style"), Element.attr(binding.soap, "style"))
    ctx = %{operation: name, style: style, binding: binding, index: index}

    %Operation{
      name: name,
      input_name: input_name,
      binding: Element.attr(binding.element, "name"),
      version: version(binding.soap_ns),
      style: style,
      soap_action: soap_op && Element.attr(soap_op, "soapAction"),
      soap_action_required: soap_op != nil and Element.attr(soap_op, "soapActionRequired") == "true",
      input: message(input, abstract_side(abstract, "input"), ctx),
      output: message(output, abstract_side(abstract, "output"), ctx),
      faults: faults(element, abstract, ctx)
    }
  end

  # A binding's overloaded operations are told apart by input name.
  defp find_abstract(operations, name, input_name) do
    named = Enum.filter(operations, &(Element.attr(&1, "name") == name))

    Enum.find(named, List.first(named), fn operation ->
      input = operation |> wsdl_children("input") |> List.first()
      input != nil and input_name != nil and Element.attr(input, "name") == input_name
    end)
  end

  defp abstract_side(nil, _side), do: nil
  defp abstract_side(abstract, side), do: abstract |> wsdl_children(side) |> List.first()

  defp style(operation_style, binding_style) do
    case operation_style || binding_style do
      "rpc" -> :rpc
      # Absent means document. So does anything unrecognized, such as a misspelling.
      _ -> :document
    end
  end

  # Messages

  defp message(nil, nil, _ctx), do: nil

  defp message(binding_side, abstract_side, ctx) do
    soap_body = binding_side && Element.child(binding_side, ctx.binding.soap_ns, "body")
    all_parts = abstract_side |> message_element(ctx) |> parts()
    headers = if binding_side, do: headers(binding_side, ctx), else: []
    body_parts = body_parts(all_parts, soap_body, headers, abstract_side, ctx)

    %Message{
      name: abstract_side && Element.attr(abstract_side, "name"),
      use: use_of(soap_body),
      namespace: soap_body && Element.attr(soap_body, "namespace"),
      encoding_style: soap_body && Element.attr(soap_body, "encodingStyle"),
      parts: body_parts,
      headers: Enum.map(headers, & &1.header),
      body: body_shape(body_parts, soap_body, ctx)
    }
  end

  defp message_element(nil, _ctx), do: nil

  defp message_element(side, ctx) do
    lookup(ctx.index.messages, Element.qname(side, Element.attr(side, "message")))
  end

  defp parts(nil), do: []

  defp parts(message) do
    for part <- wsdl_children(message, "part") do
      %Part{
        name: Element.attr(part, "name"),
        element: Element.qname(part, Element.attr(part, "element")),
        type: Element.qname(part, Element.attr(part, "type"))
      }
    end
  end

  # A `parts` attribute lists the Body's parts. Without one, the Body holds every part
  # that a header doesn't carry.
  defp body_parts(all_parts, soap_body, headers, abstract_side, ctx) do
    case soap_body && Element.attr(soap_body, "parts") do
      nil ->
        own_message = message_element(abstract_side, ctx)
        carried = for %{message: ^own_message, part: part} <- headers, do: part
        Enum.reject(all_parts, &(&1.name in carried))

      listed ->
        names = String.split(listed)
        Enum.filter(all_parts, &(&1.name in names))
    end
  end

  defp use_of(nil), do: :literal

  defp use_of(soap_body) do
    case Element.attr(soap_body, "use") do
      "encoded" -> :encoded
      _ -> :literal
    end
  end

  defp body_shape(_parts, soap_body, %{style: :rpc} = ctx) do
    namespace = (soap_body && Element.attr(soap_body, "namespace")) || ctx.binding.tns
    {:rpc, {namespace, ctx.operation}}
  end

  defp body_shape([], _soap_body, _ctx), do: :empty
  defp body_shape([%Part{element: {_, _} = element}], _soap_body, _ctx), do: {:element, element}
  defp body_shape(_parts, _soap_body, _ctx), do: :parts

  defp headers(binding_side, ctx) do
    binding_side
    |> Element.children(ctx.binding.soap_ns, "header")
    |> Enum.map(&header(&1, ctx))
  end

  defp header(element, ctx) do
    message = lookup(ctx.index.messages, Element.qname(element, Element.attr(element, "message")))
    part_name = Element.attr(element, "part")
    part = message |> parts() |> Enum.find(&(&1.name == part_name))

    %{
      message: message,
      part: part_name,
      header: %Header{
        name: part_name,
        element: part && part.element,
        type: part && part.type,
        use: use_of(element),
        namespace: Element.attr(element, "namespace")
      }
    }
  end

  defp faults(element, abstract, ctx) do
    declared = if abstract, do: wsdl_children(abstract, "fault"), else: []

    for fault <- wsdl_children(element, "fault") do
      name = Element.attr(fault, "name")
      side = Enum.find(declared, &(Element.attr(&1, "name") == name))

      %Message{
        name: name,
        use: use_of(Element.child(fault, ctx.binding.soap_ns, "fault")),
        parts: side |> message_element(ctx) |> parts()
      }
    end
  end

  # Ports

  defp ports(wsdl, bindings) do
    for service <- wsdl_children(wsdl, "service"),
        port <- wsdl_children(service, "port"),
        address = soap_address(port),
        address != nil do
      binding_name = port |> Element.qname(Element.attr(port, "binding")) |> local_name()

      %Port{
        service: Element.attr(service, "name"),
        name: Element.attr(port, "name"),
        binding: binding_name,
        location: Element.attr(address, "location"),
        version: port_version(address, binding_name, bindings)
      }
    end
  end

  defp soap_address(port), do: Enum.find(port.children, &(&1.name == "address" and &1.ns in [@soap11, @soap12]))

  defp local_name(nil), do: nil
  defp local_name({_ns, local}), do: local

  defp port_version(address, binding_name, bindings) do
    case Enum.find(bindings, &(Element.attr(&1.element, "name") == binding_name)) do
      nil -> version(address.ns)
      binding -> version(binding.soap_ns)
    end
  end
end
