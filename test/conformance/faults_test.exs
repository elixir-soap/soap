defmodule Soap.Conformance.FaultsTest do
  @moduledoc """
  Fault layer: one check for each fault found in the 1.1.1 audit, so none can return.

  Faults about the project itself, such as dependency limits and CI, have no runtime
  check here.
  """
  use ExUnit.Case

  import Soap.Conformance.Support

  alias Soap.Conformance.{Driver, Harness, WireServer, Xml}

  @moduletag capture_log: true

  @xml {"Content-Type", "text/xml; charset=utf-8"}
  @params [{"zeta", %{}, "1"}, {"alpha", %{}, "2"}]

  defp driver, do: Driver.current()
  defp check(name, fun), do: Harness.check("faults/#{name}", fun)

  defp offline(fun) do
    {result, _} = driver().without_network(fun)
    result
  end

  defp build(wsdl_opts, params, opts \\ []) do
    offline(fn ->
      assert {:ok, model} = driver().load_string(wsdl(wsdl_opts), [])
      assert {:ok, request} = driver().build_request(model, "Pay", params, opts)
      request
    end)
  end

  # Returns {result, requests the server received}.
  defp over_wire(params, opts, wsdl_opts) do
    driver().with_network(fn ->
      WireServer.with_reply(WireServer.http(200, [@xml], pay_reply()), fn server ->
        {:ok, model} = driver().load_string(wsdl([endpoint: WireServer.url(server)] ++ wsdl_opts), [])
        result = driver().call(model, "Pay", params, opts)
        {result, WireServer.requests(server)}
      end)
    end)
  end

  defp header(request, name), do: Enum.find_value(request.headers, fn {k, v} -> if k == name, do: v end)

  defp sent_children(request) do
    {:ok, doc} = Xml.parse(request.body)
    {:ok, [wrapper | _]} = Xml.body_children(doc)
    wrapper.children
  end

  defp write_wsdl(files) do
    dir = Path.join(System.tmp_dir!(), "soap_conformance_#{System.unique_integer([:positive])}")

    for {name, content} <- files do
      path = Path.join(dir, name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
    end

    dir
  end

  describe "wrong data on the wire" do
    test "invalid params are not sent" do
      check("invalid_params_not_sent", fn ->
        fields = ~s(<xsd:element name="amount" type="xsd:decimal"/>)
        {result, requests} = over_wire([{"amount", %{}, "not-a-number"}], [], fields: fields)
        assert {:error, _} = result
        assert requests == []
      end)
    end

    test "a schema using xs: accepts valid params" do
      check("xs_prefix", fn ->
        request = build([schema_prefix: "xs"], @params)
        assert Xml.valid?(request.body)
        assert Enum.map(sent_children(request), & &1.name) == ["zeta", "alpha"]
      end)
    end

    test "a schema using s: accepts valid params" do
      check("s_prefix", fn ->
        request = build([schema_prefix: "s"], @params)
        assert Xml.valid?(request.body)
        assert Enum.map(sent_children(request), & &1.name) == ["zeta", "alpha"]
      end)
    end

    test "SOAP headers are sent when the WSDL declares none" do
      check("undeclared_soap_header", fn ->
        request = build([], @params, soap_headers: [{"Token", "secret"}])
        assert {:ok, doc} = Xml.parse(request.body)
        assert [%{name: "Token", text: "secret"}] = Xml.header_children(doc)
      end)
    end

    test "custom HTTP headers keep SOAPAction and Content-Type" do
      check("custom_http_header", fn ->
        request = build([], @params, http_headers: [{"Authorization", "Bearer t"}])
        assert header(request, "Authorization") == "Bearer t"
        assert header(request, "SOAPAction") |> String.trim("\"") == "urn:t/Pay"
        assert header(request, "Content-Type") =~ "text/xml"
      end)
    end

    test "newlines and tabs in values survive" do
      check("newlines", fn ->
        request = build([], [{"zeta", %{}, "line1\nline2\tend"}, {"alpha", %{}, "x"}])
        assert hd(sent_children(request)).text == "line1\nline2\tend"
      end)
    end

    test "special characters in values are escaped" do
      check("escaping", fn ->
        request = build([], [{"zeta", %{}, "a<b&c>\"d'"}, {"alpha", %{}, "x"}])
        assert hd(sent_children(request)).text == "a<b&c>\"d'"
      end)
    end

    test "the wrapper is the element, not its type" do
      check("wrapper_element", fn ->
        request = build([type_name: "PayType"], @params)
        assert {:ok, [%{name: "Pay", ns: "urn:t"}]} = request_body(request)
      end)
    end

    test "fields follow the schema's sequence" do
      check("sequence_order", fn ->
        request = build([], [{"alpha", %{}, "2"}, {"zeta", %{}, "1"}])
        assert Enum.map(sent_children(request), & &1.name) == ["zeta", "alpha"]
      end)
    end

    test "a list value becomes repeated elements" do
      check("list_repeats", fn ->
        fields = ~s(<xsd:element name="item" type="xsd:string" maxOccurs="unbounded"/>)
        request = build([fields: fields], [{"item", %{}, "a"}, {"item", %{}, "b"}])
        assert Enum.map(sent_children(request), & &1.text) == ["a", "b"]
      end)
    end

    test "SOAP 1.2 calls use the right content type and no SOAPAction" do
      check("soap12_headers", fn ->
        request = build([soap_uri: "http://schemas.xmlsoap.org/wsdl/soap12/"], @params)
        assert header(request, "Content-Type") =~ "application/soap+xml"
        assert header(request, "SOAPAction") == nil
      end)
    end

    test "the SOAPAction header is quoted" do
      check("soapaction_quoted", fn ->
        assert header(build([], @params), "SOAPAction") == ~s("urn:t/Pay")
      end)
    end
  end

  describe "validation" do
    test "garbage in dateTime is rejected" do
      check("datetime_validation", fn ->
        fields = ~s(<xsd:element name="ts" type="xsd:dateTime"/>)
        {result, requests} = over_wire([{"ts", %{}, "garbage"}], [], fields: fields)
        assert {:error, _} = result
        assert requests == []
      end)
    end

    test "garbage around a date is rejected" do
      check("date_validation", fn ->
        fields = ~s(<xsd:element name="d" type="xsd:date"/>)
        {result, requests} = over_wire([{"d", %{}, "xx2024-99-99yy"}], [], fields: fields)
        assert {:error, _} = result
        assert requests == []
      end)
    end
  end

  describe "crashes" do
    for {name, type, value} <- [
          {"int", "xsd:int", 1},
          {"boolean", "xsd:boolean", true},
          {"long", "xsd:long", 1},
          {"double", "xsd:double", 1.5}
        ] do
      @type_name type
      @value value
      test "#{name} fields are supported" do
        check("type_#{unquote(name)}", fn ->
          request = build([fields: ~s(<xsd:element name="v" type="#{@type_name}"/>)], [{"v", %{}, @value}])
          assert hd(sent_children(request)).text == to_string(@value)
        end)
      end
    end

    test "nested complex types are supported" do
      check("nested_type", fn ->
        fields = ~s(<xsd:element name="parent" type="tns:Parent"/>)

        extra =
          ~s(<xsd:complexType name="Parent"><xsd:sequence><xsd:element name="child" type="xsd:string"/></xsd:sequence></xsd:complexType>)

        request = build([fields: fields, extra_types: extra], [{"parent", %{}, [{"child", %{}, "x"}]}])
        assert [%{name: "parent", children: [%{name: "child", text: "x"}]}] = sent_children(request)
      end)
    end

    test "Date values are supported" do
      check("date_struct", fn ->
        request = build([fields: ~s(<xsd:element name="d" type="xsd:date"/>)], [{"d", %{}, ~D[2024-01-02]}])
        assert hd(sent_children(request)).text == "2024-01-02"
      end)
    end

    test "an element name that differs from the operation works" do
      check("element_ne_operation", fn ->
        request = build([element_name: "PayRequest", type_name: "PayRequestT"], @params)
        assert {:ok, [%{name: "PayRequest"}]} = request_body(request)
      end)
    end

    test "a SOAP-1.2-only WSDL loads with default options" do
      check("soap12_only", fn ->
        doc = wsdl(soap_uri: "http://schemas.xmlsoap.org/wsdl/soap12/")
        assert {:ok, model} = offline(fn -> driver().load_string(doc, []) end)
        assert driver().operations(model) == ["Pay"]
      end)
    end

    test "a WSDL with no SOAP namespace does not crash" do
      check("no_soap_namespace", fn ->
        result = offline(fn -> driver().load_string(wsdl(soap_uri: "urn:other"), []) end)
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end

    test "SOAP 1.1 and 1.2 services work in one application" do
      check("both_versions", fn ->
        reply12 = soap12(~s(<PayOut xmlns="urn:t"><result>done</result></PayOut>))

        assert {:ok, decoded} =
                 offline(fn ->
                   {:ok, model} = driver().load_string(wsdl(soap_uri: "http://schemas.xmlsoap.org/wsdl/soap12/"), [])
                   driver().decode(model, "Pay", 200, [], reply12)
                 end)

        assert decoded |> values_at("result") |> leaves() == ["done"]
      end)
    end

    test "a missing WSDL file returns an error" do
      check("missing_file", fn ->
        assert {:error, _} = offline(fn -> driver().load("/nonexistent/soap.wsdl", []) end)
      end)
    end

    test "text that isn't XML returns an error" do
      check("wsdl_not_xml", fn ->
        assert {:error, _} = offline(fn -> driver().load_string("<html><body>503<br></body></html>", []) end)
      end)
    end

    test "an unreachable WSDL URL returns an error" do
      check("wsdl_url_refused", fn ->
        assert {:error, _} =
                 driver().with_network(fn ->
                   driver().load_url("http://127.0.0.1:#{WireServer.unused_port()}/x.wsdl", [])
                 end)
      end)
    end

    test "an HTML error page at a WSDL URL returns an error" do
      check("wsdl_url_html", fn ->
        result =
          driver().with_network(fn ->
            WireServer.with_reply(WireServer.http(503, [], "<html><body>503<br></body></html>"), fn server ->
              driver().load_url(WireServer.url(server, "/x.wsdl"), [])
            end)
          end)

        assert {:error, _} = result
      end)
    end

    test "no application config is needed" do
      check("no_app_config", fn ->
        assert {:ok, _} = driver().without_app_config(fn -> offline_without_config() end)
      end)
    end

    test "a header message prefix other than tns works" do
      check("header_prefix", fn ->
        doc =
          wsdl(
            root_extra: ~s(xmlns:h="urn:t"),
            input_extra: ~s(<soap:header message="h:In" part="body" use="literal"/>)
          )

        assert {:ok, model} = offline(fn -> driver().load_string(doc, []) end)

        assert {:ok, request} =
                 offline(fn -> driver().build_request(model, "Pay", @params, soap_headers: [{"Token", "x"}]) end)

        assert Xml.valid?(request.body)
      end)
    end
  end

  describe "empty results" do
    test "the WSDL namespace declared twice still loads" do
      check("namespace_declared_twice", fn ->
        doc =
          wsdl()
          |> String.replace("<wsdl:", "<")
          |> String.replace("</wsdl:", "</")
          |> String.replace(
            ~s(xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/"),
            ~s(xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/" xmlns="http://schemas.xmlsoap.org/wsdl/")
          )

        assert {:ok, model} = offline(fn -> driver().load_string(doc, []) end)
        assert driver().operations(model) == ["Pay"]
        assert driver().endpoints(model) == ["http://svc.example/endpoint"]
      end)
    end

    test "an empty soapAction keeps the operation" do
      check("empty_soap_action", fn ->
        assert {:ok, model} = offline(fn -> driver().load_string(wsdl(action: ""), []) end)
        assert driver().operations(model) == ["Pay"]
      end)
    end

    test "wsdl:import is followed" do
      check("wsdl_import", fn ->
        dir =
          write_wsdl([
            {"main.wsdl",
             ~s(<wsdl:definitions xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/" xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t"><wsdl:import namespace="urn:t" location="impl.wsdl"/></wsdl:definitions>)},
            {"impl.wsdl", wsdl()}
          ])

        assert {:ok, model} = offline(fn -> driver().load(Path.join(dir, "main.wsdl"), []) end)
        assert driver().operations(model) == ["Pay"]
        assert driver().endpoints(model) == ["http://svc.example/endpoint"]
      end)
    end

    test "a relative schemaLocation resolves against the WSDL URL" do
      check("relative_import_url", fn ->
        driver().with_network(fn ->
          handler = fn
            %{path: "/wsdl/service.wsdl"} ->
              imports = ~s(<xsd:import namespace="urn:x" schemaLocation="types/x.xsd"/>)
              WireServer.http(200, [{"Content-Type", "text/xml"}], wsdl(imports: imports))

            _ ->
              WireServer.http(
                200,
                [{"Content-Type", "text/xml"}],
                ~s(<xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:x"/>)
              )
          end

          WireServer.with_handler(handler, fn server ->
            driver().load_url(WireServer.url(server, "/wsdl/service.wsdl"), allow_imports_from: ["127.0.0.1"])
            assert Enum.map(WireServer.requests(server), & &1.path) == ["/wsdl/service.wsdl", "/wsdl/types/x.xsd"]
          end)
        end)
      end)
    end

    test "a failed import is reported" do
      check("failed_import_reported", fn ->
        dir =
          write_wsdl([{"main.wsdl", wsdl(imports: ~s(<xsd:import namespace="urn:x" schemaLocation="missing.xsd"/>))}])

        assert {:error, _} = offline(fn -> driver().load(Path.join(dir, "main.wsdl"), []) end)
      end)
    end
  end

  describe "result shape" do
    defp decoded(body) do
      offline(fn ->
        {:ok, model} = driver().load_string(wsdl(), [])
        driver().decode(model, "Pay", 200, [], body)
      end)
    end

    test "a repeated element is a list, however many arrive" do
      check("stable_list_shape", fn ->
        one = soap11(~s(<PayOut xmlns="urn:t"><result>r</result><item>1</item></PayOut>))
        two = soap11(~s(<PayOut xmlns="urn:t"><result>r</result><item>1</item><item>2</item></PayOut>))
        assert {:ok, a} = decoded(one)
        assert {:ok, b} = decoded(two)
        assert [["1"]] = values_at(a, "item")
        assert [["1", "2"]] = values_at(b, "item")
      end)
    end

    test "a server's choice of prefix doesn't change the result" do
      check("prefix_independent", fn ->
        plain = soap11(~s(<PayOut xmlns="urn:t"><result>r</result></PayOut>))
        prefixed = soap11(~s(<n:PayOut xmlns:n="urn:t"><n:result>r</n:result></n:PayOut>))
        assert decoded(plain) == decoded(prefixed)
      end)
    end

    test "xmlns declarations are not data" do
      check("no_xmlns_keys", fn ->
        assert {:ok, result} = decoded(pay_reply())
        refute Enum.any?(keys(result), &String.starts_with?(&1, "xmlns"))
      end)
    end

    test "xsi:nil is nil" do
      check("xsi_nil", fn ->
        body =
          soap11(
            ~s(<PayOut xmlns="urn:t" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><result xsi:nil="true"/></PayOut>)
          )

        assert {:ok, result} = decoded(body)
        assert values_at(result, "result") == [nil]
      end)
    end
  end

  describe "security" do
    test "imports can't read files outside the allowed directory" do
      check("import_confined", fn ->
        secret =
          ~s(<xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:x"><xsd:complexType name="LeakedType"><xsd:sequence/></xsd:complexType></xsd:schema>)

        doc = wsdl(imports: ~s(<xsd:import namespace="urn:x" schemaLocation="../secret.xsd"/>))
        dir = write_wsdl([{"secret.xsd", secret}, {"svc/main.wsdl", doc}])

        result = offline(fn -> driver().load(Path.join(dir, "svc/main.wsdl"), import_root: Path.join(dir, "svc")) end)

        case result do
          {:ok, model} -> refute "leakedtype" in driver().schema_types(model)
          {:error, _} -> :ok
        end
      end)
    end

    test "remote imports are not fetched by default" do
      check("no_remote_import", fn ->
        doc =
          wsdl(imports: ~s(<xsd:import namespace="urn:x" schemaLocation="http://169.254.169.254/latest/meta-data/"/>))

        dir = write_wsdl([{"main.wsdl", doc}])
        {_result, attempts} = driver().without_network(fn -> driver().load(Path.join(dir, "main.wsdl"), []) end)
        assert attempts == []
      end)
    end
  end

  defp offline_without_config, do: driver().load_string(wsdl(), [])
end
