defmodule Soap.TestTest do
  use ExUnit.Case, async: true

  import Soap.Conformance.Support, only: [wsdl: 0, pay_reply: 1]

  @params %{"zeta" => "1", "alpha" => "2"}

  defp handler(test_pid) do
    fn request ->
      send(test_pid, {:request, request})
      pay_reply("done")
    end
  end

  test "http_opts are added to the handler, not put in its place" do
    path = Path.join(System.tmp_dir!(), "soap_test_#{System.unique_integer([:positive])}.wsdl")
    File.write!(path, wsdl())
    on_exit(fn -> File.rm(path) end)

    {:ok, client} = Soap.Test.client(path, handler(self()), http_opts: [other: 1])
    assert client.opts[:http_opts][:other] == 1
    assert {:ok, _} = Soap.call(client, "Pay", @params)
    assert_received {:request, %{operation: "Pay"}}
  end

  test "takes a client that's already loaded" do
    {:ok, loaded} = Soap.from_string(wsdl(), endpoint: "http://from-client", http_opts: [other: 1])
    {:ok, client} = Soap.Test.client(loaded, handler(self()))

    assert client.opts[:http_opts][:other] == 1
    assert {:ok, _} = Soap.call(client, "Pay", @params)
    assert_received {:request, %{url: "http://from-client"}}
  end
end
