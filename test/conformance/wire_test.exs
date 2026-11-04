defmodule Soap.Conformance.WireTest do
  @moduledoc """
  Wire layer: the real HTTP client against a local server that sends exact bytes,
  including replies that no working server would send.
  """
  use ExUnit.Case

  import Soap.Conformance.Support

  alias Soap.Conformance.{Driver, Harness, WireServer}

  @moduletag capture_log: true

  @xml {"Content-Type", "text/xml; charset=utf-8"}
  @params [{"zeta", %{}, "1"}, {"alpha", %{}, "2"}]

  defp driver, do: Driver.current()

  # Sends the sample request to a server replying with `steps`, and returns the result.
  defp call_with(steps, opts \\ [], wsdl_opts \\ []) do
    driver().with_network(fn ->
      WireServer.with_reply(steps, fn server ->
        {:ok, model} = driver().load_string(wsdl([endpoint: WireServer.url(server)] ++ wsdl_opts), [])
        driver().call(model, "Pay", @params, opts)
      end)
    end)
  end

  defp assert_result(result, wanted) do
    assert {:ok, decoded} = result
    assert decoded |> values_at("result") |> leaves() == [wanted]
  end

  defp check(name, fun), do: Harness.check("wire/#{name}", fun)

  describe "successful replies" do
    test "plain 200" do
      check("ok_200", fn -> assert_result(call_with(WireServer.http(200, [@xml], pay_reply())), "done") end)
    end

    test "chunked transfer encoding" do
      body = pay_reply()
      chunked = "#{Integer.to_string(byte_size(body), 16)}\r\n#{body}\r\n0\r\n\r\n"
      head = "HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
      check("chunked", fn -> assert_result(call_with([head, chunked]), "done") end)
    end

    test "gzip content encoding" do
      steps = WireServer.http(200, [@xml, {"Content-Encoding", "gzip"}], :zlib.gzip(pay_reply()))
      check("gzip", fn -> assert_result(call_with(steps), "done") end)
    end

    test "UTF-8 byte order mark" do
      check("bom", fn -> assert_result(call_with(WireServer.http(200, [@xml], "﻿" <> pay_reply())), "done") end)
    end

    test "XML declaration after a line break" do
      steps = WireServer.http(200, [@xml], "\n" <> ~s(<?xml version="1.0"?>) <> pay_reply())
      check("leading_whitespace", fn -> assert_result(call_with(steps), "done") end)
    end

    test "ISO-8859-1 reply" do
      body = ~s(<?xml version="1.0" encoding="ISO-8859-1"?>) <> pay_reply(<<"caf", 0xE9>>)
      steps = WireServer.http(200, [{"Content-Type", "text/xml; charset=iso-8859-1"}], body)
      check("latin1", fn -> assert_result(call_with(steps), "café") end)
    end

    test "UTF-16 reply" do
      xml = ~s(<?xml version="1.0" encoding="UTF-16"?>) <> pay_reply("café")
      body = <<0xFF, 0xFE>> <> :unicode.characters_to_binary(xml, :utf8, {:utf16, :little})
      steps = WireServer.http(200, [{"Content-Type", "text/xml; charset=utf-16"}], body)
      check("utf16", fn -> assert_result(call_with(steps), "café") end)
    end

    test "CDATA section" do
      steps = WireServer.http(200, [@xml], pay_reply("<![CDATA[a<b&c]]>"))
      check("cdata", fn -> assert_result(call_with(steps), "a<b&c") end)
    end

    test "HTTP 202 with no body, as for one-way calls" do
      check("one_way_202", fn -> assert {:ok, nil} = call_with(WireServer.http(202, [], "")) end)
    end

    test "MTOM multipart reply" do
      boundary = "MIMEBoundary"

      soap =
        soap11(
          ~s(<PayOut xmlns="urn:t"><result><x:Include xmlns:x="http://www.w3.org/2004/08/xop/include" href="cid:part1"/></result></PayOut>)
        )

      body =
        "--#{boundary}\r\nContent-Type: application/xop+xml; type=\"text/xml\"\r\nContent-ID: <root>\r\n\r\n#{soap}\r\n" <>
          "--#{boundary}\r\nContent-Type: application/octet-stream\r\nContent-Transfer-Encoding: binary\r\nContent-ID: <part1>\r\n\r\nhello attach\r\n--#{boundary}--\r\n"

      content_type = ~s(multipart/related; type="application/xop+xml"; boundary="#{boundary}"; start="<root>")
      steps = WireServer.http(200, [{"Content-Type", content_type}], body)

      check("mtom", fn ->
        assert {:ok, decoded} = call_with(steps)
        assert decoded |> leaves() |> Enum.any?(&String.contains?(&1, ["hello attach", Base.encode64("hello attach")]))
      end)
    end
  end

  describe "SOAP faults" do
    test "at HTTP 500" do
      check("fault_500", fn ->
        assert {:fault, %{code: "s:Server", message: "boom"}} = call_with(WireServer.http(500, [@xml], fault11()))
      end)
    end

    test "at HTTP 200" do
      check("fault_200", fn ->
        assert {:fault, %{message: "boom"}} = call_with(WireServer.http(200, [@xml], fault11()))
      end)
    end

    test "at HTTP 400" do
      check("fault_400", fn ->
        assert {:fault, %{message: "boom"}} = call_with(WireServer.http(400, [@xml], fault11()))
      end)
    end

    test "SOAP 1.2 fault with a subcode" do
      fault =
        soap12(
          ~s(<e:Fault><e:Code><e:Value>e:Sender</e:Value><e:Subcode><e:Value xmlns:m="urn:m">m:Bad</e:Value></e:Subcode></e:Code>) <>
            ~s(<e:Reason><e:Text xml:lang="en">nope</e:Text></e:Reason></e:Fault>)
        )

      steps = WireServer.http(500, [{"Content-Type", "application/soap+xml"}], fault)

      check("fault_12_subcode", fn ->
        assert {:fault, %{code: code, message: "nope"}} =
                 call_with(steps, [], soap_uri: "http://schemas.xmlsoap.org/wsdl/soap12/")

        assert String.contains?(code, "Sender")
      end)
    end
  end

  describe "broken replies return errors" do
    test "HTML from a gateway" do
      steps = WireServer.http(502, [{"Content-Type", "text/html"}], "<html><body>Bad Gateway<br></body></html>")
      check("html_502", fn -> assert {:error, _} = call_with(steps) end)
    end

    test "well-formed HTML at HTTP 200" do
      steps = WireServer.http(200, [{"Content-Type", "text/html"}], "<html><body>Login</body></html>")
      check("html_200", fn -> assert {:error, _} = call_with(steps) end)
    end

    test "empty body at HTTP 500" do
      check("empty_500", fn -> assert {:error, _} = call_with(WireServer.http(500, [], "")) end)
    end

    test "plain text at HTTP 200" do
      check("text_200", fn ->
        assert {:error, _} = call_with(WireServer.http(200, [{"Content-Type", "text/plain"}], "OK"))
      end)
    end

    test "XML with no SOAP envelope" do
      check("no_envelope", fn -> assert {:error, _} = call_with(WireServer.http(200, [@xml], "<a>1</a>")) end)
    end

    test "non-Fault body at HTTP 400" do
      steps = WireServer.http(400, [@xml], soap11("<Err>bad</Err>"))
      check("non_fault_400", fn -> assert {:error, _} = call_with(steps) end)
    end

    test "body shorter than Content-Length" do
      head = "HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\nContent-Length: 9999\r\nConnection: close\r\n\r\n"
      check("truncated", fn -> assert {:error, _} = call_with([head, String.slice(pay_reply(), 0, 20), :close]) end)
    end

    test "connection closed before any reply" do
      check("closed_early", fn -> assert {:error, _} = call_with([:close]) end)
    end

    test "reply slower than the timeout" do
      steps = [{:sleep, 1_500} | WireServer.http(200, [@xml], pay_reply())]
      check("timeout", fn -> assert {:error, _} = call_with(steps, recv_timeout: 150) end)
    end

    test "connection refused" do
      check("refused", fn ->
        result =
          driver().with_network(fn ->
            {:ok, model} = driver().load_string(wsdl(endpoint: "http://127.0.0.1:#{WireServer.unused_port()}/x"), [])
            driver().call(model, "Pay", @params, [])
          end)

        assert {:error, _} = result
      end)
    end

    test "redirect on POST ends in a result or an error" do
      check("redirect", fn ->
        result =
          driver().with_network(fn ->
            WireServer.with_handler(
              fn
                %{path: "/soap"} -> WireServer.http(302, [{"Location", "/moved"}], "")
                _ -> WireServer.http(200, [@xml], pay_reply())
              end,
              fn server ->
                {:ok, model} = driver().load_string(wsdl(endpoint: WireServer.url(server)), [])
                driver().call(model, "Pay", @params, [])
              end
            )
          end)

        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end
  end

  describe "hostile replies" do
    test "external entity is not read" do
      canary = Path.join(System.tmp_dir!(), "soap_conformance_canary_#{System.unique_integer([:positive])}")
      File.write!(canary, "CANARY")

      body = ~s(<?xml version="1.0"?><!DOCTYPE r [<!ENTITY x SYSTEM "file://#{canary}">]>) <> pay_reply("&x;")

      check("xxe", fn ->
        result = call_with(WireServer.http(200, [@xml], body))
        assert {:error, _} = result
        refute inspect(result) =~ "CANARY"
      end)

      File.rm(canary)
    end

    test "entity expansion is refused" do
      entities = Enum.map_join(1..9, "", fn i -> ~s(<!ENTITY a#{i} "#{String.duplicate("&a#{i - 1};", 10)}">) end)
      body = ~s(<?xml version="1.0"?><!DOCTYPE r [<!ENTITY a0 "aaaaaaaaaa">#{entities}]>) <> pay_reply("&a9;")
      check("entity_bomb", fn -> assert {:error, _} = call_with(WireServer.http(200, [@xml], body)) end)
    end

    test "unique tag names create no atoms" do
      suffix = System.unique_integer([:positive])
      tags = Enum.map_join(1..3_000, "", fn i -> "<wire#{suffix}t#{i}>1</wire#{suffix}t#{i}>" end)
      steps = WireServer.http(200, [@xml], soap11("<r>#{tags}</r>"))

      check("no_atoms", fn ->
        before = :erlang.system_info(:atom_count)
        call_with(steps)
        grown = :erlang.system_info(:atom_count) - before
        assert grown < 200, "#{grown} new atoms for 3,000 unique tags"
      end)
    end
  end
end
