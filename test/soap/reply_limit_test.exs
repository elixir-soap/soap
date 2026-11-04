defmodule Soap.ReplyLimitTest do
  use ExUnit.Case, async: true

  import Soap.Conformance.Support, only: [soap11: 1, wsdl: 0, wsdl: 1]

  alias Soap.Conformance.WireServer
  alias Soap.Error

  @headers [{"Content-Type", "text/xml; charset=utf-8"}]
  @params %{"zeta" => "z", "alpha" => "a"}

  setup_all do
    {:ok, _} = Application.ensure_all_started(:req)
    :ok
  end

  defp call_server(body, opts) do
    WireServer.with_reply(WireServer.http(200, @headers, body), fn server ->
      {:ok, client} = Soap.from_string(wsdl(endpoint: WireServer.url(server)))
      Soap.call(client, "Pay", @params, opts)
    end)
  end

  defmodule IgnoresLimit do
    @behaviour Soap.HTTP

    @impl true
    def request(:post, _url, _headers, _body, opts) do
      send(self(), {:limit, opts[:max_reply_size]})
      {:ok, %{status: 200, headers: [], body: Soap.Conformance.Support.soap11("<R>1</R>")}}
    end
  end

  test "a reply within the limit decodes" do
    assert {:ok, %{"R" => "1"}} = call_server(soap11("<R>1</R>"), max_reply_size: 10_000)
  end

  test "a reply over the limit is an error" do
    assert {:error, %Error{reason: :reply_too_large}} = call_server(soap11("<R>1</R>"), max_reply_size: 10)
  end

  test "the default adapter stops reading past the limit" do
    WireServer.with_reply(WireServer.http(200, @headers, soap11("<R>1</R>")), fn server ->
      url = WireServer.url(server)
      assert {:error, :reply_too_large} = Soap.HTTP.Req.request(:post, url, [], "", max_reply_size: 10)
    end)
  end

  test "the limit can be turned off" do
    assert {:ok, %{"R" => "1"}} = call_server(soap11("<R>1</R>"), max_reply_size: :infinity)
  end

  test "a client's limit applies to its calls" do
    WireServer.with_reply(WireServer.http(200, @headers, soap11("<R>1</R>")), fn server ->
      {:ok, client} = Soap.from_string(wsdl(endpoint: WireServer.url(server)), max_reply_size: 10)
      assert {:error, %Error{reason: :reply_too_large}} = Soap.call(client, "Pay", @params)
    end)
  end

  test "an adapter that ignores the limit is still covered" do
    {:ok, client} = Soap.from_string(wsdl(endpoint: "http://localhost/x"), http: IgnoresLimit)

    assert {:error, %Error{reason: :reply_too_large}} = Soap.call(client, "Pay", @params, max_reply_size: 10)
    assert_received {:limit, 10}
  end

  test "decode_response uses the client's limit" do
    {:ok, client} = Soap.from_string(wsdl(), max_reply_size: 10)

    assert {:error, %Error{reason: :reply_too_large}} =
             Soap.decode_response(client, nil, 200, [], soap11("<R>1</R>"))
  end
end
