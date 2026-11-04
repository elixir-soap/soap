defmodule Soap.Conformance.PropertyTest do
  @moduledoc "Property layer: rules that must hold for any value, not only the samples."
  use ExUnit.Case
  use ExUnitProperties

  import Soap.Conformance.Support

  alias Soap.Conformance.{Driver, Harness, Xml}

  @moduletag capture_log: true
  @runs 100

  defp driver, do: Driver.current()

  defp offline(fun) do
    {result, _} = driver().without_network(fun)
    result
  end

  defp model do
    {:ok, model} = offline(fn -> driver().load_string(wsdl(), []) end)
    model
  end

  defp sent_text(model, value) do
    {:ok, request} = offline(fn -> driver().build_request(model, "Pay", [{"zeta", %{}, value}, {"alpha", %{}, "x"}], []) end)
    {:ok, doc} = Xml.parse(request.body)
    {:ok, [wrapper | _]} = Xml.body_children(doc)
    hd(wrapper.children).text
  end

  # Characters XML 1.0 allows. Carriage returns are left out, because XML parsers
  # are required to normalize them.
  defp xml_text(extra \\ []) do
    StreamData.string([?\s..?~, ?é, ?€, 0x1F600 | extra], min_length: 1)
    |> StreamData.filter(&(String.trim(&1) != ""))
  end

  test "text on one line reaches the server unchanged" do
    Harness.check("property/text_round_trip", fn ->
      model = model()
      check all value <- xml_text(), max_runs: @runs do
        assert sent_text(model, value) == value
      end
    end, timeout: 60_000)
  end

  test "text with newlines and tabs reaches the server unchanged" do
    Harness.check("property/multiline_round_trip", fn ->
      model = model()
      check all value <- xml_text([?\n, ?\t]), max_runs: @runs do
        assert sent_text(model, value) == value
      end
    end, timeout: 60_000)
  end

  test "any text in a reply decodes unchanged" do
    Harness.check("property/reply_round_trip", fn ->
      model = model()
      check all value <- xml_text(), max_runs: @runs do
        escaped = value |> String.replace("&", "&amp;") |> String.replace("<", "&lt;") |> String.replace(">", "&gt;")
        assert {:ok, decoded} = offline(fn -> driver().decode(model, "Pay", 200, [], pay_reply(escaped)) end)
        assert decoded |> values_at("result") |> leaves() == [String.trim(value)] or
                 decoded |> values_at("result") |> leaves() == [value]
      end
    end, timeout: 60_000)
  end

  test "decoding any bytes returns a result" do
    Harness.check("property/decode_total", fn ->
      check all bytes <- StreamData.binary(), status <- StreamData.member_of([200, 400, 500]), max_runs: @runs do
        result = driver().decode(nil, nil, status, [], bytes)
        assert match?({:ok, _}, result) or match?({:fault, _}, result) or match?({:error, _}, result)
      end
    end, timeout: 60_000)
  end

  test "decoding a cut-off reply returns a result" do
    Harness.check("property/decode_truncated", fn ->
      reply = pay_reply()
      check all cut <- StreamData.integer(0..(byte_size(reply) - 1)), max_runs: @runs do
        result = driver().decode(nil, nil, 200, [], binary_part(reply, 0, cut))
        assert {:error, _} = result
      end
    end, timeout: 60_000)
  end
end
