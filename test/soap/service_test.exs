defmodule Soap.ServiceTest do
  use ExUnit.Case, async: true

  import Soap.Conformance.Support, only: [wsdl: 1, wsdl: 0]

  alias Soap.Service
  alias Soap.Service.{Header, Message, Operation, Part, Port}

  @xsd "http://www.w3.org/2001/XMLSchema"
  @soap11 "http://schemas.xmlsoap.org/wsdl/soap/"
  @soap12 "http://schemas.xmlsoap.org/wsdl/soap12/"
  @ns ~s(xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/" xmlns:soap="#{@soap11}" xmlns:soap12="#{@soap12}" xmlns:xsd="#{@xsd}" xmlns:tns="urn:t" targetNamespace="urn:t")

  # Serves documents from a map of URL to body, and tells the test process what it fetched.
  defmodule FakeHTTP do
    @behaviour Soap.HTTP

    @impl true
    def request(:get, url, _headers, _body, opts) do
      send(opts[:test], {:fetched, url})

      case opts[:pages] do
        %{^url => body} -> {:ok, %{status: 200, headers: [], body: body}}
        _ -> {:ok, %{status: 404, headers: [], body: "<html/>"}}
      end
    end
  end

  defp http_opts(pages), do: [http: FakeHTTP, http_opts: [test: self(), pages: pages]]

  defp fetched do
    receive do
      {:fetched, url} -> [url | fetched()]
    after
      0 -> []
    end
  end

  defp tmp_dir(files) do
    dir = Path.join(System.tmp_dir!(), "soap_service_#{System.unique_integer([:positive])}")

    for {name, content} <- files do
      path = Path.join(dir, name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
    end

    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp schema(body, tns \\ ~s(targetNamespace="urn:x")),
    do: ~s(<xsd:schema xmlns:xsd="#{@xsd}" #{tns}>#{body}</xsd:schema>)

  defp doc(body), do: ~s(<wsdl:definitions #{@ns}>#{body}</wsdl:definitions>)

  defp soap_binding(style \\ "document", operations) do
    ~s(<wsdl:binding name="B" type="tns:PT"><soap:binding style="#{style}" transport="http://schemas.xmlsoap.org/soap/http"/>#{operations}</wsdl:binding>)
  end

  describe "operations" do
    test "follows binding, port type, message and part" do
      {:ok, service} = Service.from_string(wsdl())
      assert Service.operations(service) == ["Pay"]

      assert {:ok,
              %Operation{
                name: "Pay",
                binding: "B",
                version: "1.1",
                style: :document,
                soap_action: "urn:t/Pay",
                input: %Message{
                  body: {:element, {"urn:t", "Pay"}},
                  use: :literal,
                  parts: [%Part{name: "body", element: {"urn:t", "Pay"}}]
                },
                output: %Message{body: {:element, {"urn:t", "PayOut"}}}
              }} = Service.operation(service, "Pay")
    end

    test "an element name can differ from the operation name" do
      {:ok, service} = Service.from_string(wsdl(element_name: "PayRequest", type_name: "PayRequestT"))
      {:ok, operation} = Service.operation(service, "Pay")
      assert operation.input.body == {:element, {"urn:t", "PayRequest"}}
    end

    test "any prefix works, and the WSDL namespace can be declared twice" do
      doc =
        wsdl()
        |> String.replace("<wsdl:", "<")
        |> String.replace("</wsdl:", "</")
        |> String.replace(
          ~s(xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/"),
          ~s(xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/" xmlns="http://schemas.xmlsoap.org/wsdl/")
        )

      assert {:ok, service} = Service.from_string(doc)
      assert Service.operations(service) == ["Pay"]
      assert Service.endpoints(service) == ["http://svc.example/endpoint"]
    end

    test "an empty soapAction keeps the operation" do
      {:ok, service} = Service.from_string(wsdl(action: ""))
      assert {:ok, %{soap_action: ""}} = Service.operation(service, "Pay")
    end

    test "reads rpc style, and an operation can override the binding's style" do
      operations = """
      <wsdl:operation name="A"><soap:operation/><wsdl:input><soap:body use="encoded" namespace="urn:body" encodingStyle="urn:enc"/></wsdl:input></wsdl:operation>
      <wsdl:operation name="B"><soap:operation style="document"/><wsdl:input><soap:body/></wsdl:input></wsdl:operation>
      """

      messages =
        ~s(<wsdl:message name="M"><wsdl:part name="x" type="xsd:string"/><wsdl:part name="y" type="xsd:int"/></wsdl:message>)

      port_type =
        ~s(<wsdl:portType name="PT"><wsdl:operation name="A"><wsdl:input message="tns:M"/></wsdl:operation><wsdl:operation name="B"><wsdl:input message="tns:M"/></wsdl:operation></wsdl:portType>)

      {:ok, service} = Service.from_string(doc(messages <> port_type <> soap_binding("rpc", operations)))
      {:ok, a} = Service.operation(service, "A")
      {:ok, b} = Service.operation(service, "B")

      assert %{
               style: :rpc,
               input: %Message{
                 use: :encoded,
                 namespace: "urn:body",
                 encoding_style: "urn:enc",
                 body: {:rpc, {"urn:body", "A"}}
               }
             } = a

      assert [%Part{name: "x", type: {@xsd, "string"}}, %Part{name: "y"}] = a.input.parts
      assert %{style: :document, input: %Message{body: :parts}} = b
    end

    test "rpc without a body namespace uses the target namespace" do
      port_type = ~s(<wsdl:portType name="PT"><wsdl:operation name="A"/></wsdl:portType>)

      {:ok, service} =
        Service.from_string(
          doc(
            port_type <>
              soap_binding("rpc", ~s(<wsdl:operation name="A"><wsdl:input><soap:body/></wsdl:input></wsdl:operation>))
          )
        )

      {:ok, a} = Service.operation(service, "A")
      assert a.input.body == {:rpc, {"urn:t", "A"}}
    end

    test "tells one-way operations and empty messages apart" do
      messages = ~s(<wsdl:message name="None"/>)

      port_type =
        ~s(<wsdl:portType name="PT"><wsdl:operation name="A"><wsdl:input message="tns:None"/></wsdl:operation></wsdl:portType>)

      operations = ~s(<wsdl:operation name="A"><wsdl:input><soap:body/></wsdl:input></wsdl:operation>)
      {:ok, service} = Service.from_string(doc(messages <> port_type <> soap_binding(operations)))
      assert {:ok, %{input: %Message{body: :empty}, output: nil}} = Service.operation(service, "A")
    end

    test "an overloaded operation is chosen by input name" do
      messages =
        ~s(<wsdl:message name="M1"><wsdl:part name="p" element="tns:E1"/></wsdl:message><wsdl:message name="M2"><wsdl:part name="p" element="tns:E2"/></wsdl:message>)

      port_type =
        ~s(<wsdl:portType name="PT"><wsdl:operation name="A"><wsdl:input name="One" message="tns:M1"/></wsdl:operation><wsdl:operation name="A"><wsdl:input name="Two" message="tns:M2"/></wsdl:operation></wsdl:portType>)

      operations =
        ~s(<wsdl:operation name="A"><soap:operation soapAction="one"/><wsdl:input name="One"><soap:body/></wsdl:input></wsdl:operation><wsdl:operation name="A"><soap:operation soapAction="two"/><wsdl:input name="Two"><soap:body/></wsdl:input></wsdl:operation>)

      {:ok, service} = Service.from_string(doc(messages <> port_type <> soap_binding(operations)))

      assert Service.operations(service) == ["A"]

      assert {:ok, %{soap_action: "two", input: %{body: {:element, {"urn:t", "E2"}}}}} =
               Service.operation(service, "A", input: "Two")

      assert {:ok, %{soap_action: "one"}} = Service.operation(service, "A", input: "One")
    end

    test "reports an unknown operation with the names that exist" do
      {:ok, service} = Service.from_string(wsdl())
      assert {:error, {:unknown_operation, "Nope", ["Pay"]}} = Service.operation(service, "Nope")
    end

    test "a binding naming a port type that doesn't exist still finds its messages" do
      doc =
        String.replace(
          wsdl(),
          ~s(<wsdl:binding name="B" type="tns:PT">),
          ~s(<wsdl:binding name="B" type="tns:Missing">)
        )

      {:ok, service} = Service.from_string(doc)
      assert {:ok, %{input: %{body: {:element, {"urn:t", "Pay"}}}}} = Service.operation(service, "Pay")
    end

    test "a binding that isn't SOAP is ignored" do
      http =
        ~s(<wsdl:binding name="H" type="tns:PT"><http:binding xmlns:http="http://schemas.xmlsoap.org/wsdl/http/" verb="GET"/><wsdl:operation name="Other"/></wsdl:binding>)

      port =
        ~s(<wsdl:service name="S"><wsdl:port name="HP" binding="tns:H"><http:address xmlns:http="http://schemas.xmlsoap.org/wsdl/http/" location="http://h"/></wsdl:port></wsdl:service>)

      {:ok, service} = Service.from_string(doc(http <> port))
      assert Service.operations(service) == []
      assert service.ports == []
    end

    test "a prefix bound to the wrong namespace still finds the declaration" do
      doc =
        String.replace(wsdl(), ~s(xmlns:tns="urn:t"), ~s(xmlns:tns="urn:t" xmlns:other="urn:wrong"))
        |> String.replace(~s(message="tns:In"), ~s(message="other:In"))

      {:ok, service} = Service.from_string(doc)
      {:ok, operation} = Service.operation(service, "Pay")
      assert operation.input.body == {:element, {"urn:t", "Pay"}}
    end
  end

  describe "SOAP versions" do
    test "a SOAP-1.2-only WSDL loads with no options" do
      {:ok, service} = Service.from_string(wsdl(soap_uri: @soap12))
      assert {:ok, %{version: "1.2"}} = Service.operation(service, "Pay")
      assert [%Port{version: "1.2"}] = service.ports
    end

    test "both versions can be chosen, each with its own action and endpoint" do
      {:ok, service} =
        "synthetic/wsdl/divergent-bindings.wsdl" |> Soap.Conformance.Support.corpus_path() |> Service.load()

      assert {:ok, %{version: "1.1", soap_action: "urn:s/v11"} = v11} = Service.operation(service, "Ping")

      assert {:ok, %{version: "1.2", soap_action: "urn:s/v12", soap_action_required: true} = v12} =
               Service.operation(service, "Ping", version: "1.2")

      assert Service.endpoint(service, v11) == "http://localhost:9/a11"
      assert Service.endpoint(service, v12) == "http://localhost:9/a12"
      assert length(Service.endpoints(service)) == 3
    end
  end

  describe "headers" do
    test "reads declared headers, and leaves their parts out of the Body" do
      messages =
        ~s(<wsdl:message name="M"><wsdl:part name="auth" element="tns:Auth"/><wsdl:part name="body" element="tns:Req"/></wsdl:message><wsdl:message name="H"><wsdl:part name="session" type="xsd:string"/></wsdl:message>)

      port_type =
        ~s(<wsdl:portType name="PT"><wsdl:operation name="A"><wsdl:input message="tns:M"/></wsdl:operation></wsdl:portType>)

      operations =
        ~s(<wsdl:operation name="A"><wsdl:input><soap:header message="tns:M" part="auth" use="literal"/><soap:header message="tns:H" part="session" use="encoded" namespace="urn:h"/><soap:body/></wsdl:input></wsdl:operation>)

      {:ok, service} = Service.from_string(doc(messages <> port_type <> soap_binding(operations)))
      {:ok, %{input: input}} = Service.operation(service, "A")

      assert input.body == {:element, {"urn:t", "Req"}}

      assert [
               %Header{name: "auth", element: {"urn:t", "Auth"}, use: :literal},
               %Header{name: "session", type: {@xsd, "string"}, use: :encoded, namespace: "urn:h"}
             ] = input.headers
    end

    test "a parts attribute selects the Body's parts" do
      messages =
        ~s(<wsdl:message name="M"><wsdl:part name="a" element="tns:A"/><wsdl:part name="b" element="tns:B"/></wsdl:message>)

      port_type =
        ~s(<wsdl:portType name="PT"><wsdl:operation name="Op"><wsdl:input message="tns:M"/></wsdl:operation></wsdl:portType>)

      operations = ~s(<wsdl:operation name="Op"><wsdl:input><soap:body parts="b"/></wsdl:input></wsdl:operation>)
      {:ok, service} = Service.from_string(doc(messages <> port_type <> soap_binding(operations)))
      assert {:ok, %{input: %{body: {:element, {"urn:t", "B"}}}}} = Service.operation(service, "Op")
    end

    test "a header prefix other than tns works" do
      doc =
        wsdl(root_extra: ~s(xmlns:h="urn:t"), input_extra: ~s(<soap:header message="h:In" part="body" use="literal"/>))

      {:ok, service} = Service.from_string(doc)
      assert {:ok, %{input: %{headers: [%Header{name: "body"}]}}} = Service.operation(service, "Pay")
    end
  end

  describe "faults" do
    test "reads declared faults" do
      messages = ~s(<wsdl:message name="F"><wsdl:part name="detail" element="tns:Err"/></wsdl:message>)

      port_type =
        ~s(<wsdl:portType name="PT"><wsdl:operation name="A"><wsdl:fault name="Bad" message="tns:F"/></wsdl:operation></wsdl:portType>)

      operations =
        ~s(<wsdl:operation name="A"><wsdl:fault name="Bad"><soap:fault name="Bad" use="literal"/></wsdl:fault></wsdl:operation>)

      {:ok, service} = Service.from_string(doc(messages <> port_type <> soap_binding(operations)))

      assert {:ok, %{faults: [%Message{name: "Bad", parts: [%Part{element: {"urn:t", "Err"}}]}]}} =
               Service.operation(service, "A")
    end
  end

  describe "local imports" do
    test "follows wsdl:import and xsd:import, including parent directories" do
      main = doc(~s(<wsdl:import namespace="urn:t" location="sub/impl.wsdl"/>))
      impl = wsdl(imports: ~s(<xsd:import namespace="urn:x" schemaLocation="../types/x.xsd"/>))

      dir =
        tmp_dir([
          {"main.wsdl", main},
          {"sub/impl.wsdl", impl},
          {"types/x.xsd", schema(~s(<xsd:complexType name="X"/>))}
        ])

      {:ok, service} = Service.load(Path.join(dir, "main.wsdl"))
      assert Service.operations(service) == ["Pay"]
      assert Soap.Schema.type(service.schema, {"urn:x", "X"})
      assert service.unresolved_imports == []
    end

    test "an included schema takes on the includer's namespace" do
      main = wsdl(imports: ~s(<xsd:include schemaLocation="inc.xsd"/>))

      dir =
        tmp_dir([
          {"main.wsdl", main},
          {"inc.xsd", schema(~s(<xsd:element name="I" type="T"/><xsd:complexType name="T"/>), "")}
        ])

      {:ok, service} = Service.load(Path.join(dir, "main.wsdl"))
      assert %{ns: "urn:t", type: {"urn:t", "T"}} = Soap.Schema.element(service.schema, {"urn:t", "I"})
    end

    test "a query string on a location is ignored for files" do
      dir =
        tmp_dir([
          {"main.wsdl", wsdl(imports: ~s(<xsd:import namespace="urn:x" schemaLocation="x.xsd?v=1"/>))},
          {"x.xsd", schema("")}
        ])

      assert {:ok, %{unresolved_imports: []}} = Service.load(Path.join(dir, "main.wsdl"))
    end

    test "import cycles terminate" do
      for path <- ["synthetic/wsdl/circular-wsdl/a.wsdl", "synthetic/wsdl/circular-xsd/service.wsdl"] do
        assert {:ok, _} = path |> Soap.Conformance.Support.corpus_path() |> Service.load()
      end
    end

    test "a missing import is an error" do
      dir = tmp_dir([{"main.wsdl", wsdl(imports: ~s(<xsd:import namespace="urn:x" schemaLocation="missing.xsd"/>))}])
      assert {:error, {:import_failed, path, {:file, :enoent, path}}} = Service.load(Path.join(dir, "main.wsdl"))
    end

    test "failed imports can be accepted, and are still reported" do
      doc = wsdl(imports: ~s(<xsd:import namespace="urn:x" schemaLocation="missing.xsd"/>))
      dir = tmp_dir([{"main.wsdl", doc}])

      {:ok, service} = Service.load(Path.join(dir, "main.wsdl"), ignore_failed_imports: true)
      assert Service.operations(service) == ["Pay"]
      assert service.unresolved_imports == [{"missing.xsd", :import_failed}]
    end

    test "an import that isn't XML is an error" do
      dir =
        tmp_dir([
          {"main.wsdl", wsdl(imports: ~s(<xsd:import namespace="urn:x" schemaLocation="x.xsd"/>))},
          {"x.xsd", "not xml"}
        ])

      assert {:error, {:import_failed, _, {:invalid_xml, _}}} = Service.load(Path.join(dir, "main.wsdl"))
    end

    test "an import that is another kind of document is an error" do
      dir =
        tmp_dir([
          {"main.wsdl", wsdl(imports: ~s(<xsd:import namespace="urn:x" schemaLocation="x.xsd"/>))},
          {"x.xsd", "<html/>"}
        ])

      assert {:error, {:import_failed, _, {:not_a_wsdl_or_schema, "html"}}} = Service.load(Path.join(dir, "main.wsdl"))
    end
  end

  describe "import security" do
    test ":import_root confines local imports" do
      doc = wsdl(imports: ~s(<xsd:import namespace="urn:x" schemaLocation="../secret.xsd"/>))
      dir = tmp_dir([{"svc/main.wsdl", doc}, {"secret.xsd", schema(~s(<xsd:complexType name="Leaked"/>))}])

      {:ok, service} = Service.load(Path.join(dir, "svc/main.wsdl"), import_root: Path.join(dir, "svc"))
      assert Soap.Schema.type(service.schema, {"urn:x", "Leaked"}) == nil
      assert service.unresolved_imports == [{"../secret.xsd", :outside_import_root}]
    end

    test "a sibling directory with the same prefix is outside :import_root" do
      doc = wsdl(imports: ~s(<xsd:import namespace="urn:x" schemaLocation="../svc-other/x.xsd"/>))
      dir = tmp_dir([{"svc/main.wsdl", doc}, {"svc-other/x.xsd", schema("")}])
      {:ok, service} = Service.load(Path.join(dir, "svc/main.wsdl"), import_root: Path.join(dir, "svc"))
      assert [{_, :outside_import_root}] = service.unresolved_imports
    end

    test "absolute paths and file URLs are never read" do
      doc =
        wsdl(
          imports:
            ~s(<xsd:import namespace="urn:a" schemaLocation="/etc/passwd"/><xsd:import namespace="urn:b" schemaLocation="file:///etc/passwd"/><xsd:import namespace="urn:c" schemaLocation="ftp://h/x"/>)
        )

      dir = tmp_dir([{"main.wsdl", doc}])

      {:ok, service} = Service.load(Path.join(dir, "main.wsdl"))

      assert service.unresolved_imports == [
               {"/etc/passwd", :absolute_path},
               {"file:///etc/passwd", :scheme_not_allowed},
               {"ftp://h/x", :scheme_not_allowed}
             ]
    end

    test "a local WSDL fetches nothing by default" do
      doc = wsdl(imports: ~s(<xsd:import namespace="urn:a" schemaLocation="http://169.254.169.254/latest/meta-data/"/>))
      dir = tmp_dir([{"main.wsdl", doc}])

      {:ok, service} = Service.load(Path.join(dir, "main.wsdl"), http_opts(%{}))
      assert fetched() == []
      assert service.unresolved_imports == [{"http://169.254.169.254/latest/meta-data/", :host_not_allowed}]
    end

    test "a remote WSDL can't read local files" do
      doc = wsdl(imports: ~s(<xsd:import namespace="urn:a" schemaLocation="file:///etc/passwd"/>))
      {:ok, service} = Service.load("http://h/s.wsdl", http_opts(%{"http://h/s.wsdl" => doc}))
      assert service.unresolved_imports == [{"file:///etc/passwd", :scheme_not_allowed}]
    end

    test "a remote WSDL can't reach other hosts unless they are allowed" do
      location = "http://other/x.xsd"
      doc = wsdl(imports: ~s(<xsd:import namespace="urn:x" schemaLocation="#{location}"/>))
      pages = %{"http://h/s.wsdl" => doc, location => schema("")}

      {:ok, blocked} = Service.load("http://h/s.wsdl", http_opts(pages))
      assert blocked.unresolved_imports == [{location, :host_not_allowed}]
      assert fetched() == ["http://h/s.wsdl"]

      {:ok, allowed} = Service.load("http://h/s.wsdl", [allow_imports_from: ["other"]] ++ http_opts(pages))
      assert allowed.unresolved_imports == []
      assert fetched() == ["http://h/s.wsdl", location]

      {:ok, all} = Service.load("http://h/s.wsdl", [allow_imports_from: :all] ++ http_opts(pages))
      assert all.unresolved_imports == []
    end

    test "a string has no location to resolve against, unless given one" do
      doc = wsdl(imports: ~s(<xsd:import namespace="urn:x" schemaLocation="x.xsd"/>))
      {:ok, service} = Service.from_string(doc)
      assert service.unresolved_imports == [{"x.xsd", :no_base_location}]

      dir = tmp_dir([{"x.xsd", schema(~s(<xsd:complexType name="X"/>))}])
      {:ok, based} = Service.from_string(doc, base: Path.join(dir, "main.wsdl"))
      assert Soap.Schema.type(based.schema, {"urn:x", "X"})
    end

    test "a DOCTYPE is refused" do
      for name <- ["xxe-external-entity", "entity-expansion-bomb"] do
        path = Soap.Conformance.Support.corpus_path("synthetic/negative/#{name}.wsdl")
        assert {:error, :doctype_not_allowed} = Service.load(path)
      end
    end
  end

  describe "remote loading" do
    test "resolves relative imports against the importing document, keeping query strings" do
      main =
        wsdl(
          imports:
            ~s(<xsd:import namespace="urn:x" schemaLocation="types/x.xsd"/><xsd:import namespace="urn:y" schemaLocation="?xsd=1"/>)
        )

      pages = %{
        "http://h/wsdl/s.wsdl" => main,
        "http://h/wsdl/types/x.xsd" => schema(""),
        "http://h/wsdl/s.wsdl?xsd=1" => schema("")
      }

      assert {:ok, _} = Service.load("http://h/wsdl/s.wsdl", http_opts(pages))
      assert fetched() == ["http://h/wsdl/s.wsdl", "http://h/wsdl/types/x.xsd", "http://h/wsdl/s.wsdl?xsd=1"]
    end

    test "a failed fetch or an error status is an error" do
      assert {:error, {:http_status, 404, "http://h/x"}} = Service.load("http://h/x", http_opts(%{}))

      main = wsdl(imports: ~s(<xsd:import namespace="urn:x" schemaLocation="x.xsd"/>))

      assert {:error, {:import_failed, "http://h/x.xsd", {:http_status, 404, _}}} =
               Service.load("http://h/s", http_opts(%{"http://h/s" => main}))
    end
  end

  describe "bad input" do
    test "returns errors" do
      assert {:error, {:file, :enoent, _}} = Service.load("/nonexistent/x.wsdl")
      assert {:error, {:invalid_xml, _}} = Service.from_string("<html><body>503<br></body></html>")
      assert {:error, {:not_a_wsdl, "html"}} = Service.from_string("<html/>")

      assert {:error, {:unsupported, :wsdl_2_0}} =
               Service.from_string(~s(<description xmlns="http://www.w3.org/ns/wsdl"/>))
    end

    test "a WSDL with no SOAP namespace loads with nothing in it" do
      assert {:ok, %{operations: [], ports: []}} = Service.from_string(wsdl(soap_uri: "urn:other"))
    end

    test "a bare schema loads" do
      assert {:ok, %{operations: []} = service} =
               Service.from_string(schema(~s(<xsd:element name="E" type="xsd:string"/>)))

      assert Soap.Schema.element(service.schema, {"urn:x", "E"})
    end

    test "needs no application configuration" do
      assert Application.get_all_env(:nonexistent) == []
      assert {:ok, _} = Service.from_string(wsdl())
    end
  end
end
