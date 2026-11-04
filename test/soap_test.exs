defmodule SoapTest do
  use ExUnit.Case, async: true

  import Soap.Conformance.Support, only: [wsdl: 0, wsdl: 1, soap11: 1, pay_reply: 1]
  import ExUnit.CaptureLog

  alias Soap.{Attachment, Error, Fault, Multipart, Raw, Request, Response, WSSE}
  alias Soap.Conformance.{Support, WireServer, Xml}

  @params %{"zeta" => "1", "alpha" => "2"}

  defp client(handler, opts \\ [], wsdl_opts \\ []) do
    {:ok, client} = Soap.from_string(wsdl(wsdl_opts), [http: Soap.Test, http_opts: [handler: handler]] ++ opts)
    client
  end

  defp echoing(test_pid \\ self()) do
    fn request ->
      send(test_pid, {:request, request})
      pay_reply("done")
    end
  end

  describe "load" do
    test "from a file and from a string" do
      assert {:ok, %Soap.Client{} = client} = Soap.load(Support.corpus_path("synthetic/wsdl/divergent-bindings.wsdl"))
      assert Soap.operations(client) == ["Ping"]
      assert {:ok, _} = Soap.from_string(wsdl())
    end

    test "errors are wrapped" do
      assert {:error, %Error{reason: {:file, :enoent, _}}} = Soap.load("/nope.wsdl")
      assert {:error, %Error{reason: {:not_a_wsdl, "html"}}} = Soap.from_string("<html/>")
    end
  end

  describe "call" do
    test "returns the decoded result, shaped by the schema" do
      client = client(fn _ -> soap11(~s(<PayOut xmlns="urn:t"><result>r</result><item>1</item></PayOut>)) end)
      assert Soap.call(client, "Pay", @params) == {:ok, %{"PayOut" => %{"result" => "r", "item" => ["1"]}}}
    end

    test "sends to the WSDL's address, with the operation's headers" do
      assert {:ok, _} = Soap.call(client(echoing()), "Pay", @params)

      assert_received {:request,
                       %{url: "http://svc.example/endpoint", headers: headers, operation: "Pay", params: params}}

      assert {"SOAPAction", ~s("urn:t/Pay")} in headers
      assert {"Content-Type", "text/xml; charset=utf-8"} in headers
      assert params == @params
    end

    test "options on the client and the call combine, and the call wins" do
      client = client(echoing(), endpoint: "http://from-client", http_headers: [{"X-A", "1"}])
      assert {:ok, _} = Soap.call(client, "Pay", @params)
      assert_received {:request, %{url: "http://from-client"}}
      assert {:ok, _} = Soap.call(client, "Pay", @params, endpoint: "http://from-call")
      assert_received {:request, %{url: "http://from-call", headers: headers}}
      assert {"X-A", "1"} in headers
    end

    test "a custom header replaces a standard one of the same name" do
      assert {:ok, _} = Soap.call(client(echoing()), "Pay", @params, http_headers: [{"content-type", "text/plain"}])
      assert_received {:request, %{headers: headers}}
      assert {"content-type", "text/plain"} in headers
      refute {"Content-Type", "text/xml; charset=utf-8"} in headers
    end

    test "invalid params aren't sent" do
      fields = ~s(<xsd:element name="amount" type="xsd:decimal"/>)

      assert {:error, %Error{reason: {:invalid_param, "Pay/amount", _}}} =
               Soap.call(client(echoing(), [], fields: fields), "Pay", %{amount: "x"})

      refute_received {:request, _}
    end

    test "unknown operations say what exists" do
      assert {:error, %Error{reason: {:unknown_operation, "Nope", ["Pay"]}}} = Soap.call(client(echoing()), "Nope")
    end

    test "with no address, says so" do
      doc = wsdl() |> String.replace(~r/<wsdl:service.*<\/wsdl:service>/s, "")
      {:ok, client} = Soap.from_string(doc, http: Soap.Test, http_opts: [handler: echoing()])
      assert {:error, %Error{reason: :no_endpoint}} = Soap.call(client, "Pay", @params)
      assert {:ok, _} = Soap.call(client, "Pay", @params, endpoint: "http://x")
    end

    test "transport failures are errors" do
      client = client(fn _ -> {:error, :timeout} end)
      assert {:error, %Error{reason: {:transport, :timeout}}} = Soap.call(client, "Pay", @params)
    end

    test "Faults are errors" do
      client = client(fn _ -> Soap.Test.fault("s:Server", "boom") end)
      assert {:error, %Fault{code: "s:Server", message: "boom", status: 500}} = Soap.call(client, "Pay", @params)
    end

    test "call! returns or raises" do
      assert %{"PayOut" => _} = Soap.call!(client(echoing()), "Pay", @params)
      assert_raise Fault, fn -> Soap.call!(client(fn _ -> Soap.Test.fault("c", "m") end), "Pay", @params) end
      assert_raise Error, fn -> Soap.call!(client(echoing()), "Nope") end
    end
  end

  describe "request" do
    test "returns the whole response" do
      body =
        ~s(<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Header><T>1</T></s:Header><s:Body><PayOut xmlns="urn:t"><result>r</result></PayOut></s:Body></s:Envelope>)

      client = client(fn _ -> {201, [{"x-h", "v"}], body} end)

      assert {:ok,
              %Response{
                status: 201,
                headers: [{"x-h", "v"}],
                body: ^body,
                soap_headers: %{"T" => "1"},
                result: %{"PayOut" => _}
              }} =
               Soap.request(client, "Pay", @params)
    end
  end

  describe "build_request" do
    test "builds without sending" do
      assert {:ok,
              %Request{
                url: "http://svc.example/endpoint",
                operation: "Pay",
                version: "1.1",
                body: body,
                attachments: []
              }} =
               Soap.build_request(client(echoing()), "Pay", @params)

      assert Xml.valid?(body)
      refute_received {:request, _}
    end
  end

  describe "SOAP versions" do
    test "1.2 uses its content type and no SOAPAction" do
      client = client(echoing(), [], soap_uri: "http://schemas.xmlsoap.org/wsdl/soap12/")
      {:ok, request} = Soap.build_request(client, "Pay", @params)
      assert [{"Content-Type", ~s(application/soap+xml; charset=utf-8; action="urn:t/Pay")}] = request.headers
      assert request.version == "1.2"
    end

    test "a service offering both can be asked for either" do
      {:ok, client} = Soap.load(Support.corpus_path("synthetic/wsdl/divergent-bindings.wsdl"))
      {:ok, v11} = Soap.build_request(client, "Ping", %{v: "x"})
      {:ok, v12} = Soap.build_request(client, "Ping", %{v: "x"}, version: "1.2")
      assert v11.url == "http://localhost:9/a11"
      assert v12.url == "http://localhost:9/a12"
      assert {:ok, %{ns: "http://www.w3.org/2003/05/soap-envelope"}} = Xml.parse(v12.body)
    end

    test "1.1 and 1.2 clients work side by side" do
      v11 = client(fn _ -> soap11("<R>1</R>") end)

      v12 =
        client(fn _ -> Soap.Test.reply("R", 2, version: "1.2") end, [],
          soap_uri: "http://schemas.xmlsoap.org/wsdl/soap12/"
        )

      assert {:ok, %{"R" => "1"}} = Soap.call(v11, "Pay", @params)
      assert {:ok, %{"R" => "2"}} = Soap.call(v12, "Pay", @params)
    end
  end

  describe "overloaded operations" do
    test "are chosen with :input" do
      {:ok, client} = Soap.load(Support.corpus_path("synthetic/wsdl/overloaded-operations.wsdl"))
      {:ok, by_number} = Soap.build_request(client, "Ping", 5, input: "ByNumber")
      assert {"SOAPAction", ~s("urn:s/number")} in by_number.headers
      assert by_number.body =~ "PingB"
    end
  end

  describe "WS-Security" do
    test "sends a UsernameToken with a plain password" do
      token = WSSE.username_token("ann", "s<cret")
      {:ok, request} = Soap.build_request(client(echoing()), "Pay", @params, wsse: token)
      {:ok, doc} = Xml.parse(request.body)

      assert [%{name: "Security", children: [%{name: "UsernameToken", children: [user, password, nonce, created]}]}] =
               Xml.header_children(doc)

      assert %{name: "Username", text: "ann"} = user
      assert %{name: "Password", text: "s<cret"} = password
      assert Map.values(password.attrs) |> hd() =~ "PasswordText"
      assert nonce.name == "Nonce"
      assert created.name == "Created"

      assert %{{"http://schemas.xmlsoap.org/soap/envelope/", "mustUnderstand"} => "1"} =
               hd(Xml.header_children(doc)).attrs
    end

    test "digest follows the spec: base64(sha1(nonce + created + password))" do
      token = WSSE.username_token("ann", "secret", digest: true)
      nonce = <<1, 2, 3, 4>>
      now = ~U[2024-01-02 03:04:05.000Z]
      %Raw{xml: xml} = WSSE.header(token, nonce, now)
      xml = IO.iodata_to_binary(xml)
      expected = :crypto.hash(:sha, [nonce, "2024-01-02T03:04:05.000Z", "secret"]) |> Base.encode64()
      assert xml =~ expected
      assert xml =~ "PasswordDigest"
      refute xml =~ "secret"
    end

    test "can add a timestamp, and leave out mustUnderstand" do
      token = WSSE.username_token("a", "b", timestamp: 60, must_understand: false)
      xml = token |> WSSE.header() |> Map.fetch!(:xml) |> IO.iodata_to_binary()
      assert xml =~ "wsu:Expires"
      refute xml =~ "mustUnderstand"
    end

    test "every header gets a fresh nonce" do
      token = WSSE.username_token("a", "b")
      refute WSSE.header(token) == WSSE.header(token)
    end

    test "inspect hides the password" do
      refute inspect(WSSE.username_token("a", "topsecret")) =~ "topsecret"
    end
  end

  describe "attachments" do
    defp binary_client(handler) do
      client(handler, [], fields: ~s(<xsd:element name="file" type="xsd:base64Binary"/>))
    end

    test "mtom: true sends a multipart request the decoder can read back" do
      test_pid = self()

      handler = fn request ->
        send(test_pid, {:request, request})
        pay_reply("ok")
      end

      assert {:ok, _} = Soap.call(binary_client(handler), "Pay", %{file: <<0, 1, 255>>}, mtom: true)
      assert_received {:request, %{params: %{"file" => <<0, 1, 255>>}, headers: headers}}
      {_, content_type} = List.keyfind(headers, "Content-Type", 0)
      assert content_type =~ ~s(multipart/related; type="application/xop+xml")
      assert List.keyfind(headers, "SOAPAction", 0)
    end

    test "an Attachment value works without the option" do
      {:ok, request} =
        Soap.build_request(binary_client(echoing()), "Pay", %{file: %Attachment{data: "x", content_type: "image/png"}})

      assert [%Attachment{id: id, content_type: "image/png"}] = request.attachments
      assert IO.iodata_to_binary(request.body) =~ "Content-ID: <#{id}>"
    end

    test ":attachments adds extra parts" do
      {:ok, request} = Soap.build_request(client(echoing()), "Pay", @params, attachments: [%Attachment{data: "extra"}])
      {_, content_type} = List.keyfind(request.headers, "Content-Type", 0)

      assert {:ok, root, [%Attachment{data: "extra"}]} =
               Multipart.parse(content_type, IO.iodata_to_binary(request.body))

      assert Xml.valid?(root)
    end
  end

  describe "raw XML" do
    test "goes into params and headers" do
      {:ok, request} =
        Soap.build_request(client(echoing()), "Pay", %{"zeta" => %Raw{xml: "<x/>"}}, headers: [%Raw{xml: "<h/>"}])

      assert request.body =~ "<x/>"
      assert request.body =~ "<h/>"
    end
  end

  describe "telemetry" do
    setup do
      test_pid = self()
      id = "test-#{inspect(self())}"

      :telemetry.attach_many(
        id,
        [[:soap, :request, :start], [:soap, :request, :stop]],
        fn event, measurements, metadata, _ ->
          if metadata[:tag] == test_pid, do: send(test_pid, {event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(id) end)
      {:ok, opts: [telemetry_metadata: %{tag: test_pid}]}
    end

    test "emits start and stop, with no secrets", %{opts: opts} do
      opts =
        opts ++
          [
            endpoint: "http://user:pass@h/p?key=secret",
            http_headers: [{"Authorization", "Bearer t"}],
            wsse: WSSE.username_token("a", "topsecret")
          ]

      assert {:ok, _} = Soap.call(client(echoing()), "Pay", @params, opts)
      assert_received {[:soap, :request, :start], %{system_time: _}, start}
      assert_received {[:soap, :request, :stop], %{duration: _}, %{outcome: :ok, status: 200} = stop}

      for metadata <- [start, stop] do
        assert metadata.operation == "Pay"
        assert metadata.url == "http://h/p"
        assert {"Authorization", "[masked]"} in metadata.request_headers
        refute inspect(metadata) =~ "topsecret"
        refute Map.has_key?(metadata, :request_body)
      end
    end

    test "reports Faults and errors", %{opts: opts} do
      Soap.call(client(fn _ -> Soap.Test.fault("c", "m") end), "Pay", @params, opts)
      assert_received {[:soap, :request, :stop], _, %{outcome: :fault, status: 500}}
      Soap.call(client(fn _ -> {:error, :timeout} end), "Pay", @params, opts)
      assert_received {[:soap, :request, :stop], _, %{outcome: :error, reason: {:transport, :timeout}}}
      Soap.call(client(fn _ -> {502, "x"} end), "Pay", @params, opts)
      assert_received {[:soap, :request, :stop], _, %{outcome: :error, status: 502, reason: {:http_status, 502}}}
    end

    test "log_bodies adds the body, with passwords masked", %{opts: opts} do
      token = WSSE.username_token("ann", "topsecret")
      assert {:ok, _} = Soap.call(client(echoing()), "Pay", @params, opts ++ [wsse: token, log_bodies: true])
      assert_received {[:soap, :request, :stop], _, %{request_body: body}}
      assert body =~ "ann"
      assert body =~ "[masked]"
      refute body =~ "topsecret"
    end
  end

  describe "HTTP adapters" do
    for adapter <- [Soap.HTTP.Req, Soap.HTTP.HTTPoison] do
      @adapter adapter

      test "#{inspect(adapter)} sends a call and reads its reply" do
        WireServer.with_reply(WireServer.http(200, [{"Content-Type", "text/xml"}], pay_reply("done")), fn server ->
          {:ok, client} = Soap.from_string(wsdl(endpoint: WireServer.url(server)), http: @adapter)

          assert {:ok, %{"PayOut" => %{"result" => "done"}}} =
                   Soap.call(client, "Pay", @params, timeout: 2_000, connect_timeout: 2_000)

          assert [%{method: "POST", path: "/soap", body: body, headers: headers}] = WireServer.requests(server)
          assert body =~ "zeta"
          assert {"soapaction", ~s("urn:t/Pay")} in headers
        end)
      end

      test "#{inspect(adapter)} reports a timeout and a refused connection" do
        WireServer.with_reply([{:sleep, 800}], fn server ->
          {:ok, client} = Soap.from_string(wsdl(endpoint: WireServer.url(server)), http: @adapter)
          assert {:error, %Error{reason: {:transport, _}}} = Soap.call(client, "Pay", @params, timeout: 50)
        end)

        {:ok, client} =
          Soap.from_string(wsdl(endpoint: "http://127.0.0.1:#{WireServer.unused_port()}/x"), http: @adapter)

        assert {:error, %Error{reason: {:transport, _}}} = Soap.call(client, "Pay", @params)
      end

      test "#{inspect(adapter)} loads a WSDL by URL, following redirects" do
        handler = fn
          %{path: "/old"} -> WireServer.http(302, [{"Location", "/new"}], "")
          _ -> WireServer.http(200, [], wsdl())
        end

        WireServer.with_handler(handler, fn server ->
          assert {:ok, client} = Soap.load(WireServer.url(server, "/old"), http: @adapter)
          assert Soap.operations(client) == ["Pay"]
        end)
      end
    end
  end

  describe "logging" do
    test "the default logger reports calls without secrets" do
      Soap.Telemetry.attach_default_logger(level: :warning)
      on_exit(&Soap.Telemetry.detach_default_logger/0)

      log =
        capture_log(fn ->
          Soap.call(client(echoing()), "Pay", @params, endpoint: "http://u:secret@h/p?k=secret")
        end)

      assert log =~ "SOAP Pay ok status=200 url=http://h/p"
      refute log =~ "secret"
    end
  end
end
