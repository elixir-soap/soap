defmodule Soap.Conformance.GoldenTest do
  @moduledoc """
  Golden layer: request and response pairs from node-soap's test suite.

  A request must mean the same as `request.xml`. Prefixes and declarations don't
  matter, but names, namespaces, order, attributes and text do. A response must
  decode to a result that holds every value in `response.json`, because this layer
  doesn't assume 2.0's exact result shape.

  Samples that depend on node-soap's own options get no request check.
  """
  use ExUnit.Case

  alias Soap.Conformance.{Driver, Harness, Support, Xml}

  @moduletag capture_log: true

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

  defp to_nodes(key, nil), do: [{key, %{}, ""}]
  defp to_nodes(key, scalar), do: [{key, %{}, scalar}]

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

    if has.("request.xml") and has.("request.json") and not node_only? and not raw? do
      test "#{label} request" do
        Harness.check("golden/#{@dir}/request", fn ->
          offline(fn ->
            assert {:ok, model} = load(@dir)
            json = @dir |> file("request.json") |> File.read!()
            params = json |> Jason.decode!(objects: :ordered_objects) |> to_params()
            assert {:ok, request} = driver().build_request(model, @op, params, [])
            assert {:ok, got} = Support.request_body(request)
            assert {:ok, doc} = @dir |> file("request.xml") |> File.read!() |> Xml.parse()
            assert {:ok, want} = Xml.body_children(doc)
            assert Enum.map(got, &Xml.simplify/1) == Enum.map(want, &Xml.simplify/1)
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
