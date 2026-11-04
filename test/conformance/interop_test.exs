defmodule Soap.Conformance.InteropTest do
  @moduledoc """
  Interop layer: real calls to real SOAP stacks, in Docker.

  Public servers can't cover MTOM, WS-Security or stable rpc/encoded, so these do:
  Apache CXF, PHP's SoapServer and node-soap. Run it with:

      docker compose -f test/interop/docker-compose.yml up -d --build --wait
      mix test --only interop
  """
  use ExUnit.Case

  alias Soap.{Attachment, Error, Fault, WSSE}

  @moduletag :interop

  @cxf "http://localhost:18081"
  @php "http://localhost:18082"
  @node "http://localhost:18083"

  defp client(url, opts \\ []) do
    endpoint = url |> String.split("?") |> hd()
    assert {:ok, client} = Soap.load(url, [endpoint: endpoint] ++ opts)
    client
  end

  defp php(opts \\ []) do
    assert {:ok, client} = Soap.load("#{@php}/rpc.wsdl", [endpoint: "#{@php}/rpc"] ++ opts)
    client
  end

  defp node_client(opts \\ []) do
    assert {:ok, client} = Soap.load("#{@node}/doc?wsdl", [endpoint: "#{@node}/doc"] ++ opts)
    client
  end

  describe "Apache CXF" do
    test "document/literal, SOAP 1.1" do
      assert {:ok, %{"greetResponse" => %{"result" => "Hello, Ann"}}} =
               Soap.call(client("#{@cxf}/doc?wsdl"), "greet", %{name: "Ann"})
    end

    test "document/literal round trip with nested data and typed values" do
      item = %{"name" => "Tea & <milk>", "quantity" => 2, "price" => 1.5, "urgent" => true, "tags" => ["a", "b"]}

      assert {:ok, %{"echoItemResponse" => %{"item" => out}}} =
               Soap.call(client("#{@cxf}/doc?wsdl"), "echoItem", %{item: item})

      assert out == %{"name" => "Tea & <milk>", "quantity" => 3, "price" => 1.5, "urgent" => true, "tags" => ["a", "b"]}
    end

    test "one item in a repeating field comes back as a list" do
      item = %{"name" => "x", "quantity" => 0, "price" => 0, "urgent" => false, "tags" => ["only"]}

      assert {:ok, %{"echoItemResponse" => %{"item" => %{"tags" => ["only"]}}}} =
               Soap.call(client("#{@cxf}/doc?wsdl"), "echoItem", %{item: item})
    end

    test "a server exception is a Fault" do
      assert {:error, %Fault{code: code, message: "boom", status: 500}} =
               Soap.call(client("#{@cxf}/doc?wsdl"), "fail", %{message: "boom"})

      assert code =~ "Server"
    end

    test "SOAP 1.2" do
      client = client("#{@cxf}/doc12?wsdl")
      assert {:ok, %{"greetResponse" => %{"result" => "Hello, Ann"}}} = Soap.call(client, "greet", %{name: "Ann"})
      assert {:error, %Fault{code: code, message: "boom"}} = Soap.call(client, "fail", %{message: "boom"})
      assert code =~ "Receiver"
    end

    test "a wrong operation for the service is a Fault, not a crash" do
      {:ok, request} = Soap.build_request(client("#{@cxf}/doc?wsdl"), "greet", %{name: "Ann"})

      {:ok, reply} =
        Soap.HTTP.Req.request(:post, request.url, request.headers, String.replace(request.body, "greet", "nope"), [])

      assert {:error, %Fault{}} = Soap.decode_response(nil, nil, reply.status, reply.headers, reply.body)
    end

    test "rpc/literal" do
      assert {:ok, %{"addResponse" => %{"sum" => 5}}} = Soap.call(client("#{@cxf}/rpc?wsdl"), "add", %{a: 2, b: 3})
    end

    test "MTOM in both directions, SOAP 1.1" do
      bytes = :crypto.strong_rand_bytes(100_000)

      assert {:ok, %{"reverseResponse" => %{"data" => out}}} =
               Soap.call(client("#{@cxf}/files?wsdl"), "reverse", %{data: bytes}, mtom: true)

      assert out == bytes |> :binary.bin_to_list() |> Enum.reverse() |> :binary.list_to_bin()
    end

    test "MTOM in both directions, SOAP 1.2" do
      assert {:ok, %{"reverseResponse" => %{"data" => <<3, 2, 1>>}}} =
               Soap.call(client("#{@cxf}/files12?wsdl"), "reverse", %{data: <<1, 2, 3>>}, mtom: true)
    end

    test "an Attachment struct goes by MTOM" do
      attachment = %Attachment{data: "abc", content_type: "text/plain"}

      assert {:ok, %{"reverseResponse" => %{"data" => "cba"}}} =
               Soap.call(client("#{@cxf}/files?wsdl"), "reverse", %{data: attachment})
    end

    test "base64 inline reaches an MTOM service too" do
      assert {:ok, %{"reverseResponse" => %{"data" => "cba"}}} =
               Soap.call(client("#{@cxf}/files?wsdl"), "reverse", %{data: "abc"})
    end

    test "WS-Security with a plain password" do
      client = client("#{@cxf}/secure?wsdl")

      assert {:ok, %{"whoAmIResponse" => %{"result" => "authenticated"}}} =
               Soap.call(client, "whoAmI", %{}, wsse: WSSE.username_token("ann", "secret"))

      assert {:error, %Fault{}} = Soap.call(client, "whoAmI", %{}, wsse: WSSE.username_token("ann", "wrong"))
      assert {:error, %Fault{}} = Soap.call(client, "whoAmI", %{})
    end

    test "WS-Security with a password digest" do
      client = client("#{@cxf}/secure-digest?wsdl")

      assert {:ok, %{"whoAmIResponse" => %{"result" => "authenticated"}}} =
               Soap.call(client, "whoAmI", %{}, wsse: WSSE.username_token("ann", "secret", digest: true))

      assert {:error, %Fault{}} =
               Soap.call(client, "whoAmI", %{}, wsse: WSSE.username_token("ann", "wrong", digest: true))
    end

    test "every adapter works" do
      opts = [http: Soap.HTTP.HTTPoison]
      assert {:ok, %{"greetResponse" => _}} = Soap.call(client("#{@cxf}/doc?wsdl", opts), "greet", %{name: "A"})
    end
  end

  describe "PHP SoapServer" do
    test "rpc/encoded scalars keep their types" do
      assert {:ok, %{"echoStringResponse" => %{"return" => "héllo <&>"}}} =
               Soap.call(php(), "echoString", %{value: "héllo <&>"})

      assert {:ok, %{"addResponse" => %{"return" => 5}}} = Soap.call(php(), "add", %{a: 2, b: 3})
      assert {:ok, %{"echoFlagResponse" => %{"return" => false}}} = Soap.call(php(), "echoFlag", %{flag: true})
    end

    test "soapenc arrays in both directions" do
      assert {:ok, %{"echoStringsResponse" => %{"return" => ["b", "a"]}}} =
               Soap.call(php(), "echoStrings", %{values: ["a", "b"]})
    end

    test "a struct with arrays and shared references" do
      assert {:ok, %{"getOrderResponse" => %{"return" => order}}} = Soap.call(php(), "getOrder", %{id: 7})
      assert %{"id" => 7, "total" => 12.5, "paid" => true, "lines" => ["a", "b"]} = order
      assert order["buyer"]["name"] == "Ann"
      assert order["payer"]["name"] == "Ann"
    end

    test "a SoapFault is a Fault" do
      assert {:error, %Fault{code: code, message: "nope"}} = Soap.call(php(), "fail", %{message: "nope"})
      assert code =~ "Server"
    end
  end

  describe "node-soap" do
    test "document/literal round trip" do
      params = %{"message" => "hi", "count" => 1, "tags" => ["a", "b"], "nested" => %{"id" => 1, "ok" => true}}
      assert {:ok, %{"EchoResponse" => out}} = Soap.call(node_client(), "Echo", params)
      assert out == params
    end

    test "WS-Security, plain and digest" do
      client = node_client()

      assert {:ok, %{"SecureResponse" => %{"message" => "hello ann"}}} =
               Soap.call(client, "Secure", %{}, wsse: WSSE.username_token("ann", "secret"))

      assert {:ok, %{"SecureResponse" => _}} =
               Soap.call(client, "Secure", %{}, wsse: WSSE.username_token("ann", "secret", digest: true))

      assert {:error, reason} = Soap.call(client, "Secure", %{}, wsse: WSSE.username_token("ann", "wrong"))
      assert match?(%Fault{}, reason) or match?(%Error{}, reason)
    end
  end
end
