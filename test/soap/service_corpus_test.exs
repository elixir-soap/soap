defmodule Soap.ServiceCorpusTest do
  @moduledoc """
  Compares the WSDL model with facts computed independently of it, for every fixture.

  This goes deeper than the conformance parser layer, which can only ask what v1 can
  also answer.
  """
  use ExUnit.Case, async: true

  alias Soap.Conformance.Support
  alias Soap.{Schema, Service}

  defmodule Refuse do
    @moduledoc false
    @behaviour Soap.HTTP
    @impl true
    def request(_method, _url, _headers, _body, _opts), do: {:error, :network_disabled}
  end

  defp load(entry), do: Service.load(Support.corpus_path(entry["local"]), http: Refuse)

  defp binding_facts(service, name) do
    service.operations
    |> Enum.filter(&(&1.name == name))
    |> Enum.map(&{&1.version, &1.soap_action, &1.style, input_use(&1)})
    |> Enum.sort()
  end

  # An operation with no input, such as a notification, counts as literal in the facts.
  defp input_use(%{input: nil}), do: :literal
  defp input_use(%{input: input}), do: input.use

  defp truth_facts(op) do
    op["bindings"]
    |> Enum.map(fn b ->
      style = if b["style"] == "rpc", do: :rpc, else: :document
      use = if b["use"] == "encoded", do: :encoded, else: :literal
      {b["version"], b["action"], style, use}
    end)
    |> Enum.sort()
  end

  # The fact script reads a wrapper from a message with exactly one part, and from the
  # first of any overloaded operations. A part that a header carries isn't in the Body.
  defp assert_wrapper(service, name, %{"name" => wrapper, "namespace" => namespace}) do
    inputs = for %{name: ^name, input: %{} = input} <- service.operations, do: input

    if inputs != [] do
      assert Enum.any?(inputs, fn input ->
               case input.body do
                 {_kind, {ns, ^wrapper}} -> namespace == nil or ns == namespace
                 :empty -> input.headers != []
                 _ -> false
               end
             end),
             "wrapper differs for #{name}: #{inspect(Enum.map(inputs, & &1.body))}"
    end
  end

  defp assert_wrapper(_service, _name, nil), do: :ok

  for entry <- Support.manifest(), is_map(entry["truth"]), entry["expect"] == "parse" do
    @entry entry

    test "#{Support.test_label(Path.relative_to(entry["local"], "wsdl"))}" do
      assert {:ok, service} = load(@entry)
      truth = @entry["truth"]

      assert Enum.sort(Service.operations(service)) == truth["operations"] |> Map.keys() |> Enum.sort()

      for {name, op} <- truth["operations"] do
        assert binding_facts(service, name) == truth_facts(op), "bindings differ for #{name}"
        assert_wrapper(service, name, op["wrapper"])
      end

      ports = Enum.map(truth["ports"], &{&1["service"], &1["port"], &1["location"]})
      assert Enum.sort(ports) == service.ports |> Enum.map(&{&1.service, &1.name, &1.location}) |> Enum.sort()
    end
  end

  test "schema references resolve, apart from skipped imports and gaps in the fixtures" do
    gaps = [
      # These fixtures reference declarations in files they don't include.
      "wsdl/php__php-src/ext/soap/tests/soap12/soap12-test.wsdl",
      "wsdl/php__php-src/ext/soap/tests/bugs/bug27742.wsdl",
      "wsdl/vpulim__node-soap/test/request-response-samples/createData__should_generate_complex_type_request/soap.wsdl"
    ]

    unexplained =
      for entry <- Support.manifest(), is_map(entry["truth"]), entry["expect"] == "parse", entry["local"] not in gaps do
        {:ok, service} = load(entry)
        {entry["local"], Schema.unresolved_references(service.schema), service.unresolved_imports}
      end
      |> Enum.filter(fn {_local, missing, skipped} -> missing != [] and skipped == [] end)

    assert unexplained == []
  end
end
