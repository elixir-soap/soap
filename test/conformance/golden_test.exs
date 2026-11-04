defmodule Soap.Conformance.GoldenTest do
  @moduledoc """
  Golden layer: request and response pairs from node-soap's test suite.

  A request must mean the same as `request.xml`. Prefixes and declarations don't
  matter, but names, namespaces, order, attributes and text do. A response must
  decode to a result that holds every value in `response.json`, because this layer
  doesn't assume 2.0's exact result shape.

  Requests are built with validation off, because many samples send fields that their
  WSDL doesn't declare. Samples that depend on node-soap's own options get no request
  check, and neither do the samples listed in `@disagreements`.
  """
  use ExUnit.Case

  alias Soap.Conformance.{Driver, Harness, Support, Xml}

  @moduletag capture_log: true

  # Where node-soap's output depends on its own conventions, or differs from the WSDL.
  @disagreements %{
    "Login__unsupported_response_name_returned_and_local_xs_schema_missed" =>
      "node-soap ignores the namespace in soap:body, which the WSDL 1.1 binding requires for rpc.",
    "multiCall__rpc_stype_request_xsi_attributes" =>
      "node-soap sends its own attributes for nested untyped arrays, and no encodingStyle.",
    "fooOp__should_return_back_good_response_object" =>
      "The schema declares Request1 in its target namespace, but node-soap sends it with none.",
    "GetItems__one_item_array_response" =>
      "The type is declared in a qualified schema, so Item belongs to that schema's namespace, not the wrapper's.",
    "getAvailability__should_not_fail_without_children" =>
      "node-soap ignores the namespace in soap:body, which the WSDL 1.1 binding requires for rpc.",
    "Dummy__should_parse_nil" =>
      "A nil for an element the schema doesn't call nillable is left out. node-soap sends xsi:nil.",
    "Dummy__should_escape_xml" =>
      "A nil for an element the schema doesn't call nillable is left out. node-soap sends xsi:nil.",
    "Message__overriding_namespace_prefix" =>
      "The sample uses a node-soap key prefix to change an element's namespace.",
    "createData__should_generate_complex_type_request" =>
      "The sample uses a node-soap key prefix to change an element's namespace."
  }

  defp driver, do: Driver.current()
  defp file(dir, name), do: Path.join([Support.corpus_path("golden/node-soap"), dir, name])

  defp offline(fun) do
    {result, _} = driver().without_network(fun)
    result
  end

  defp load(dir), do: driver().load(file(dir, "soap.wsdl"), driver().tolerant_opts(["1.1"]))

  # Converts node-soap's JSON conventions into driver params, keeping key order.
  defp to_params(%Jason.OrderedObject{values: values}) do
    Enum.flat_map(values, fn
      {key, _} when key in ["attributes", "$attributes", "$value", "$xml"] -> []
      {key, value} -> to_nodes(key, value)
    end)
  end

  defp to_params(_scalar), do: []

  defp to_nodes(key, values) when is_list(values), do: Enum.flat_map(values, &to_nodes(key, &1))

  defp to_nodes(key, %Jason.OrderedObject{values: values} = object) do
    attrs =
      values
      |> Enum.filter(fn {k, _} -> k in ["attributes", "$attributes"] end)
      |> Enum.flat_map(fn {_, %Jason.OrderedObject{values: pairs}} -> pairs end)
      |> Map.new()

    value =
      case List.keyfind(values, "$value", 0) do
        {_, %Jason.OrderedObject{} = inner} -> to_params(inner)
        {_, scalar} -> scalar
        nil -> to_params(object)
      end

    [{key, attrs, value}]
  end

  defp to_nodes(key, nil), do: [{key, %{}, nil}]
  defp to_nodes(key, scalar), do: [{key, %{}, scalar}]

  # encodingStyle is correct on an encoded body, though node-soap leaves it out.
  defp comparable(node) do
    attrs = node.attrs |> Enum.reject(fn {{_ns, name}, _} -> name == "encodingStyle" end) |> Map.new()
    Xml.simplify(%{node | attrs: attrs, children: []}) |> put_children(Enum.map(node.children, &comparable/1))
  end

  defp put_children({ns, name, attrs, text}, []), do: {ns, name, attrs, text}
  defp put_children({ns, name, attrs, _}, children), do: {ns, name, attrs, children}

  defp json_leaves(value) when is_map(value), do: value |> Map.values() |> Enum.flat_map(&json_leaves/1)
  defp json_leaves(value) when is_list(value), do: Enum.flat_map(value, &json_leaves/1)
  defp json_leaves(nil), do: []
  defp json_leaves(value), do: [value |> to_string() |> String.trim()]

  root = Support.corpus_path("golden/node-soap")
  dirs = root |> File.ls!() |> Enum.filter(&File.dir?(Path.join(root, &1))) |> Enum.sort()

  for dir <- dirs do
    @dir dir
    base = Path.join(root, dir)
    @op dir |> String.split("__") |> hd()
    label = Support.test_label(dir)
    has = &File.exists?(Path.join(base, &1))
    node_only? = Enum.any?(["wsdl_options.json", "wsdl_options.js", "options.json"], has)
    raw? = has.("request.json") and String.contains?(File.read!(Path.join(base, "request.json")), "$xml")

    disagreement? = Map.has_key?(@disagreements, dir)

    if has.("request.xml") and has.("request.json") and not node_only? and not raw? and not disagreement? do
      test "#{label} request" do
        Harness.check("golden/#{@dir}/request", fn ->
          offline(fn ->
            assert {:ok, model} = load(@dir)
            json = @dir |> file("request.json") |> File.read!()
            params = json |> Jason.decode!(objects: :ordered_objects) |> to_params()
            assert {:ok, request} = driver().build_request(model, @op, params, validate: false)
            assert {:ok, got} = Support.request_body(request)
            assert {:ok, doc} = @dir |> file("request.xml") |> File.read!() |> Xml.parse()
            assert {:ok, want} = Xml.body_children(doc)
            assert Enum.map(got, &comparable/1) == Enum.map(want, &comparable/1)
          end)
        end)
      end
    end

    if has.("response.xml") and has.("response.json") do
      test "#{label} response" do
        Harness.check("golden/#{@dir}/response", fn ->
          offline(fn ->
            assert {:ok, model} = load(@dir)
            body = @dir |> file("response.xml") |> File.read!()
            assert {:ok, result} = driver().decode(model, @op, 200, [], body)
            want = @dir |> file("response.json") |> File.read!() |> Jason.decode!() |> json_leaves()
            got = result |> Support.leaves() |> Enum.map(&String.trim/1)
            assert want -- got == []
          end)
        end)
      end
    end

    if has.("response.xml") and has.("error_response.json") do
      test "#{label} fault" do
        Harness.check("golden/#{@dir}/fault", fn ->
          offline(fn ->
            assert {:ok, model} = load(@dir)
            body = @dir |> file("response.xml") |> File.read!()
            assert {:fault, %{code: _, message: _}} = driver().decode(model, @op, 500, [], body)
          end)
        end)
      end
    end
  end
end
