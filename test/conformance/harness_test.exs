defmodule Soap.Conformance.HarnessTest do
  @moduledoc "Tests for the test tools. A broken ratchet or comparer would hide real failures."
  use ExUnit.Case

  alias Soap.Conformance.{Harness, Support, WireServer, Xml}

  describe "ratchet" do
    setup do
      saved = :persistent_term.get({Harness, :known})
      :persistent_term.put({Harness, :known}, %{"_self/listed" => "known"})
      on_exit(fn -> :persistent_term.put({Harness, :known}, saved) end)
    end

    test "a passing, unlisted check passes" do
      assert Harness.check("_self/unlisted", fn -> :ok end) == :ok
    end

    test "a failing, listed check passes" do
      assert Harness.check("_self/listed", fn -> raise "known" end) == :ok
    end

    test "a failing, unlisted check fails" do
      assert_raise ExUnit.AssertionError, ~r/new failure/, fn ->
        Harness.check("_self/unlisted", fn -> raise "new" end)
      end
    end

    test "a passing, listed check fails until it is removed" do
      assert_raise ExUnit.AssertionError, ~r/now passes/, fn ->
        Harness.check("_self/listed", fn -> :ok end)
      end
    end

    test "an exit counts as a failure" do
      assert_raise ExUnit.AssertionError, ~r/new failure/, fn ->
        Harness.check("_self/unlisted", fn -> exit(:boom) end)
      end
    end

    test "a timeout counts as a failure" do
      assert_raise ExUnit.AssertionError, ~r/timeout/, fn ->
        Harness.check("_self/unlisted", fn -> Process.sleep(:infinity) end, timeout: 20)
      end
    end
  end

  describe "XML comparison" do
    defp simple(xml) do
      {:ok, doc} = Xml.parse(xml)
      Xml.simplify(doc)
    end

    test "prefixes and declarations don't matter" do
      assert simple(~s(<a:r xmlns:a="u"><a:x>1</a:x></a:r>)) == simple(~s(<r xmlns="u"><x>1</x></r>))
    end

    test "namespaces matter" do
      refute simple(~s(<r xmlns="u"/>)) == simple(~s(<r xmlns="v"/>))
    end

    test "an unprefixed child of a prefixed parent has no namespace" do
      assert {_, "r", _, [{nil, "x", _, _}]} = simple(~s(<a:r xmlns:a="u"><x/></a:r>))
    end

    test "order matters" do
      refute simple("<r><a/><b/></r>") == simple("<r><b/><a/></r>")
    end

    test "attribute order doesn't matter, but values do" do
      assert simple(~s(<r a="1" b="2"/>)) == simple(~s(<r b="2" a="1"/>))
      refute simple(~s(<r a="1"/>)) == simple(~s(<r a="2"/>))
    end

    test "whitespace between elements doesn't matter, but text does" do
      assert simple("<r>\n  <a/>\n</r>") == simple("<r><a/></r>")
      refute simple("<r>a b</r>") == simple("<r>a  b</r>")
    end

    test "entities are decoded" do
      assert {nil, "r", _, "a<b"} = simple("<r>a&lt;b</r>")
    end

    test "invalid documents are errors" do
      refute Xml.valid?("<a><b></a>")
      refute Xml.valid?("<x:a/>")
      refute Xml.valid?(~s(<env:Envelope xmlns:="u" xmlns:env="v"/>))
      refute Xml.valid?("")
    end
  end

  describe "result helpers" do
    test "values_at ignores prefixes" do
      assert Support.values_at(%{"n:r": %{"n:v": "1"}}, "v") == ["1"]
      assert Support.values_at(%{"r" => [%{"v" => 1}, %{"v" => 2}]}, "v") == [1, 2]
    end

    test "leaves flattens maps, lists and keyword lists" do
      assert Enum.sort(Support.leaves(%{a: [b: "1", b: "2"], c: 3})) == ["1", "2", "3"]
    end
  end

  describe "wire server" do
    test "records the request and sends the exact reply" do
      steps = WireServer.http(201, [{"X-Test", "yes"}], "hello")

      WireServer.with_reply(steps, fn server ->
        {:ok, reply} = Soap.HTTP.HTTPoison.request(:post, WireServer.url(server, "/p"), [{"A", "b"}], "body", [])
        assert reply.status == 201
        assert reply.body == "hello"
        assert [%{method: "POST", path: "/p", body: "body", headers: headers}] = WireServer.requests(server)
        assert {"a", "b"} in headers
      end)
    end
  end
end
