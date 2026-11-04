defmodule Soap.Conformance.ParserTest do
  @moduledoc """
  Parser layer: every fixture in `test/corpus/manifest.json` is loaded and checked
  against facts computed independently by `tools/corpus/add_truth.py`.
  """
  use ExUnit.Case

  alias Soap.Conformance.{Driver, Harness, Support, Xml}

  @moduletag capture_log: true
  @external_resource Support.corpus_path("manifest.json")

  @envelope %{"1.1" => "http://schemas.xmlsoap.org/soap/envelope/", "1.2" => "http://www.w3.org/2003/05/soap-envelope"}

  defp driver, do: Driver.current()
  defp path(entry), do: Support.corpus_path(entry["local"])

  defp offline(fun) do
    {result, _attempts} = driver().without_network(fun)
    result
  end

  defp versions(entry) do
    entry["truth"]["operations"]
    |> Enum.flat_map(fn {_, op} -> Enum.map(op["bindings"], & &1["version"]) end)
    |> Enum.uniq()
  end

  defp request_version(entry), do: if("1.1" in versions(entry), do: "1.1", else: "1.2")

  defp bindings(op, version), do: Enum.filter(op["bindings"], &(&1["version"] == version))

  # Calls fun with each operation's built request. Operations are capped so the
  # largest fixtures don't dominate the run.
  defp each_request(entry, fun) do
    offline(fn ->
      assert {:ok, model} = driver().load(path(entry), driver().tolerant_opts(versions(entry)))
      version = request_version(entry)

      entry["truth"]["operations"]
      |> Enum.filter(fn {_, op} -> bindings(op, version) != [] end)
      |> Enum.sort()
      |> Enum.take(8)
      |> Enum.each(fn {name, op} ->
        assert {:ok, request} = driver().build_request(model, name, [], soap_version: version)
        fun.(name, op, version, request)
      end)
    end)
  end

  defp header(request, name) do
    Enum.find_value(request.headers, fn {k, v} -> if String.downcase(to_string(k)) == name, do: to_string(v) end)
  end

  for entry <- Support.manifest() do
    @entry entry
    label = Support.test_label(Path.relative_to(entry["local"], "wsdl"))
    prefix = "parser/#{entry["id"]}"
    expect = entry["expect"]

    cond do
      expect == "parse" and is_map(entry["truth"]) ->
        test "#{label} loads" do
          Harness.check("#{unquote(prefix)}/loads", fn ->
            assert {:ok, _} = offline(fn -> driver().load(path(@entry), []) end)
          end)
        end

        if entry["truth"]["operations"] != %{} do
          test "#{label} finds every operation" do
            Harness.check("#{unquote(prefix)}/operations", fn ->
              assert {:ok, model} = offline(fn -> driver().load(path(@entry), []) end)
              assert Enum.sort(driver().operations(model)) == @entry["truth"]["operations"] |> Map.keys() |> Enum.sort()
            end)
          end

          test "#{label} builds well-formed requests" do
            Harness.check("#{unquote(prefix)}/request_xml", fn ->
              each_request(@entry, fn name, _op, _version, request ->
                assert Xml.valid?(request.body),
                       "#{name}: not valid XML: #{inspect(request.body) |> String.slice(0, 160)}"
              end)
            end)
          end

          test "#{label} uses the right envelope" do
            Harness.check("#{unquote(prefix)}/request_envelope", fn ->
              each_request(@entry, fn _name, _op, version, request ->
                assert {:ok, %{name: "Envelope", ns: ns}} = Xml.parse(request.body)
                assert ns == @envelope[version]
              end)
            end)
          end

          test "#{label} wraps the body in the right element" do
            Harness.check("#{unquote(prefix)}/request_wrapper", fn ->
              each_request(@entry, fn name, op, _version, request ->
                case op["wrapper"] do
                  nil ->
                    :ok

                  wrapper ->
                    assert {:ok, [first | _]} = Support.request_body(request)

                    assert first.name == wrapper["name"],
                           "#{name}: wrapper is #{first.name}, expected #{wrapper["name"]}"

                    if wrapper["namespace"] do
                      assert first.ns == wrapper["namespace"],
                             "#{name}: namespace is #{inspect(first.ns)}, expected #{wrapper["namespace"]}"
                    end
                end
              end)
            end)
          end

          test "#{label} sends the right SOAP action" do
            Harness.check("#{unquote(prefix)}/request_action", fn ->
              each_request(@entry, fn name, op, version, request ->
                actions = op |> bindings(version) |> Enum.map(&(&1["action"] || ""))

                sent =
                  if version == "1.1" do
                    (header(request, "soapaction") || "") |> String.trim("\"")
                  else
                    case Regex.run(~r/action="([^"]*)"/, header(request, "content-type") || "") do
                      [_, action] -> action
                      nil -> ""
                    end
                  end

                assert sent in actions, "#{name}: sent #{inspect(sent)}, expected one of #{inspect(actions)}"
              end)
            end)
          end

          test "#{label} sends the right content type" do
            Harness.check("#{unquote(prefix)}/request_content_type", fn ->
              each_request(@entry, fn _name, _op, version, request ->
                wanted = if version == "1.1", do: "text/xml", else: "application/soap+xml"
                assert String.starts_with?(header(request, "content-type") || "", wanted)
              end)
            end)
          end
        end

        if entry["truth"]["ports"] != [] do
          test "#{label} finds an endpoint" do
            Harness.check("#{unquote(prefix)}/endpoint", fn ->
              assert {:ok, model} = offline(fn -> driver().load(path(@entry), []) end)
              locations = Enum.map(@entry["truth"]["ports"], & &1["location"])
              assert Enum.any?(driver().endpoints(model), &(&1 in locations))
            end)
          end
        end

      expect in ["return {:error, _}", "reject, and read no file", "reject without expanding"] ->
        test "#{label} is rejected with an error" do
          Harness.check("#{unquote(prefix)}/rejected", fn ->
            assert {:error, _} = offline(fn -> driver().load(path(@entry), []) end)
          end)
        end

      expect == "parse with no fetch unless the import host is allowed" ->
        test "#{label} fetches nothing by default" do
          Harness.check("#{unquote(prefix)}/no_fetch", fn ->
            {_result, attempts} = driver().without_network(fn -> driver().load(path(@entry), []) end)
            assert attempts == []
          end)
        end

      true ->
        test "#{label} does not crash" do
          Harness.check("#{unquote(prefix)}/no_crash", fn ->
            result = offline(fn -> driver().load(path(@entry), []) end)
            assert match?({:ok, _}, result) or match?({:error, _}, result)
          end)
        end
    end
  end
end
