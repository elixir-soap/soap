defmodule Soap.GeneratorTest do
  use ExUnit.Case

  import ExUnit.CaptureIO
  import Soap.Conformance.Support, only: [wsdl: 1, wsdl: 0, corpus_path: 1, pay_reply: 1]

  alias Soap.{Generator, Service}

  defp generate(doc \\ wsdl(), module \\ "Gen#{System.unique_integer([:positive])}.Client") do
    {:ok, service} = Service.from_string(doc)
    {module, Generator.generate(service, module, "http://example.com/s?wsdl")}
  end

  defp compiled(source) do
    [{module, _} | _] = Code.compile_string(source)
    module
  end

  test "generates a compiling module with a function per operation" do
    {name, source} = generate()
    module = compiled(source)
    assert inspect(module) == name
    assert function_exported?(module, :pay, 1)
    assert function_exported?(module, :pay, 3)
    assert function_exported?(module, :client, 0)
    assert source =~ ~s|`"zeta"` - `String.t()`|
    assert source =~ "http://example.com/s?wsdl"
  end

  test "the generated function makes a real call" do
    {_name, source} = generate()
    module = compiled(source)
    {:ok, client} = Soap.from_string(wsdl(), http: Soap.Test, http_opts: [handler: fn _ -> pay_reply("done") end])
    assert {:ok, %{"PayOut" => %{"result" => "done"}}} = module.pay(client, %{"zeta" => "1"})
  end

  test "types follow the schema" do
    extra =
      ~s(<xsd:complexType name="Order"><xsd:sequence><xsd:element name="id" type="xsd:long"/><xsd:element name="ok" type="xsd:boolean"/><xsd:element name="d" type="xsd:date"/><xsd:element name="t" type="xsd:dateTime"/><xsd:element name="r" type="xsd:double"/><xsd:element name="lines" type="xsd:string" maxOccurs="unbounded"/><xsd:element name="next" type="tns:Order" minOccurs="0"/></xsd:sequence></xsd:complexType>)

    {_name, source} = generate(wsdl(fields: ~s(<xsd:element name="order" type="tns:Order"/>), extra_types: extra))
    compiled(source)
    assert source =~ "@type order ::"
    assert source =~ ~s|`"id"` - `integer()`|
    assert source =~ ~s|`"ok"` - `boolean()`|
    assert source =~ ~s|`"lines"` - `[String.t()]`|
    assert source =~ ~s|`"next"` - `order()`|
    assert source =~ "Date.t()"
    assert source =~ "DateTime.t()"
  end

  test "unsafe names become valid functions" do
    doc =
      wsdl()
      |> String.replace(~s(name="Pay"><wsdl:input), ~s(name="send-Now"><wsdl:input))
      |> String.replace(
        ~s(<wsdl:operation name="Pay"><soap:operation),
        ~s(<wsdl:operation name="send-Now"><soap:operation)
      )

    {_name, source} = generate(doc)
    assert function_exported?(compiled(source), :send__now, 3) or source =~ "def send"
  end

  test "names Kernel already uses get a suffix" do
    doc =
      wsdl()
      |> String.replace(~s(<wsdl:operation name="Pay"><soap:operation), ~s(<wsdl:operation name="send"><soap:operation))

    {_name, source} = generate(doc)
    assert source =~ "def send_call("
    compiled(source)
  end

  test "a sample of real fixtures generates compiling code" do
    fixtures = ~w(
      synthetic/wsdl/overloaded-operations.wsdl
      synthetic/wsdl/divergent-bindings.wsdl
      synthetic/wsdl/substitution-group-inline.wsdl
    )

    wsdls =
      Path.wildcard(corpus_path("wsdl/vpulim__node-soap/test/wsdl/*.wsdl")) ++
        Path.wildcard(corpus_path("wsdl/php__php-src/ext/soap/tests/interop/**/*.wsdl")) ++
        Enum.map(fixtures, &corpus_path/1)

    wsdls = Enum.take_every(wsdls, 6) ++ Enum.map(fixtures, &corpus_path/1)
    assert length(wsdls) >= 5

    for {path, index} <- Enum.with_index(wsdls) do
      case Service.load(path, ignore_failed_imports: true) do
        {:ok, %{operations: [_ | _]} = service} ->
          source = Generator.generate(service, "GenAll#{index}.Client", path)
          assert is_atom(compiled(source)), path

        _ ->
          :ok
      end
    end
  end

  test "types that reach themselves through references terminate" do
    for name <- ["recursive_with_ref", "recursive_with_ref2"] do
      path = corpus_path("wsdl/vpulim__node-soap/test/wsdl/#{name}.wsdl")

      if File.exists?(path) do
        {:ok, service} = Service.load(path)
        assert is_binary(Generator.generate(service, "GenRec.#{Macro.camelize(name)}", path))
      end
    end
  end

  describe "mix soap.gen" do
    setup do
      dir = Path.join(System.tmp_dir!(), "soap_gen_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      path = Path.join(dir, "s.wsdl")
      File.write!(path, wsdl())
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir, path: path}
    end

    defp run(args), do: capture_io(fn -> Mix.Tasks.Soap.Gen.run(args) end)

    test "writes the file", %{dir: dir, path: path} do
      output = Path.join(dir, "out/client.ex")
      assert run([path, "--module", "My.Gen.Client1", "--output", output]) =~ "1 operations"
      assert File.read!(output) =~ "defmodule My.Gen.Client1"
    end

    test "won't overwrite without --force", %{dir: dir, path: path} do
      output = Path.join(dir, "client.ex")
      File.write!(output, "old")
      assert_raise Mix.Error, ~r/--force/, fn -> run([path, "--module", "A", "--output", output]) end
      run([path, "--module", "A", "--output", output, "--force"])
      assert File.read!(output) =~ "defmodule A"
    end

    test "checks its arguments", %{path: path} do
      assert_raise Mix.Error, ~r/--module/, fn -> run([path]) end
      assert_raise Mix.Error, ~r/Invalid module/, fn -> run([path, "--module", "not valid"]) end
      assert_raise Mix.Error, ~r/one WSDL/, fn -> run(["--module", "A"]) end

      assert_raise Mix.Error, ~r/Couldn't load/, fn ->
        run(["/nope.wsdl", "--module", "A", "--output", "/tmp/never-used.ex"])
      end
    end

    test "reports skipped imports", %{dir: dir} do
      path = Path.join(dir, "i.wsdl")
      File.write!(path, wsdl(imports: ~s(<xsd:import namespace="urn:x" schemaLocation="http://h/x.xsd"/>)))
      assert run([path, "--module", "A", "--output", Path.join(dir, "a.ex")]) =~ "host_not_allowed"
    end
  end
end
