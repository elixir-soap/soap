defmodule Soap.Conformance.WholeCorpusTest do
  @moduledoc """
  Nightly layer: every harvested WSDL, measured against score floors.

  Too large to keep in the repository, so `tools/corpus/harvest.sh` downloads it.
  Each score in `test/corpus/scores/<driver>.json` is a floor: falling more than 1% below
  one fails the run, and `CONFORMANCE_UPDATE=1` resets the floors to the current scores.
  The 1% allows for upstream repositories and public WSDLs changing. The offline layers
  catch smaller regressions.

      CORPUS_DIR=/tmp/corpus mix test --only nightly
  """
  use ExUnit.Case

  import Soap.Conformance.Support

  alias Soap.Conformance.{Driver, Harness, Xml}

  @moduletag :nightly
  @moduletag capture_log: true
  @moduletag timeout: :infinity

  defp driver, do: Driver.current()
  defp scores_path, do: corpus_path("scores/#{Driver.name()}.json")

  # A crash or hang in one file must not stop the measurement.
  defp attempt(fun, timeout \\ 20_000) do
    task = Task.Supervisor.async_nolink(Soap.Conformance.Tasks, fun)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> :crashed
    end
  end

  defp valid_request?(model, name, wrappers, version) do
    case driver().build_request(model, name, [], soap_version: version) do
      {:ok, request} ->
        want = get_in(wrappers, [name, "expect"])

        with true <- Xml.valid?(request.body),
             {:ok, [first | _]} <- request_body(request) do
          want == nil or first.name == want
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  defp measure(corpus, entry) do
    path = Path.join(corpus, entry["path"])
    wanted = Enum.uniq(entry["ops11"] ++ entry["ops12"])
    versions = if(entry["ops11"] != [], do: ["1.1"], else: []) ++ if(entry["ops12"] != [], do: ["1.2"], else: [])
    version = List.first(versions) || "1.1"
    default = attempt(fn -> driver().load(path, []) end)
    tolerant = attempt(fn -> driver().load(path, driver().tolerant_opts(versions)) end)

    has_all = fn
      {:ok, model} -> wanted -- driver().operations(model) == []
      _ -> false
    end

    results =
      case tolerant do
        {:ok, model} ->
          for name <- wanted |> Enum.sort() |> Enum.take(8) do
            attempt(fn -> valid_request?(model, name, entry["wrappers"], version) end, 5_000) == true
          end

        _ ->
          List.duplicate(false, min(length(wanted), 8))
      end

    %{
      "files" => 1,
      "loaded" => if(match?({:ok, _}, default), do: 1, else: 0),
      "files_with_operations" => if(wanted != [], do: 1, else: 0),
      "all_operations" => if(wanted != [] and has_all.(default), do: 1, else: 0),
      "all_operations_tolerant" => if(wanted != [] and has_all.(tolerant), do: 1, else: 0),
      "requests" => length(results),
      "valid_requests" => Enum.count(results, & &1)
    }
  end

  @tag :nightly
  test "scores don't fall below the floors" do
    corpus = System.get_env("CORPUS_DIR") || flunk("Set CORPUS_DIR. See tools/corpus/harvest.sh.")
    entries = corpus |> Path.join("expected.json") |> File.read!() |> Jason.decode!()
    start_supervised!({Task.Supervisor, name: Soap.Conformance.Tasks})

    {scores, _attempts} =
      driver().without_network(fn ->
        Enum.reduce(entries, %{}, fn entry, acc ->
          Map.merge(acc, measure(corpus, entry), fn _key, a, b -> a + b end)
        end)
      end)

    IO.puts("\nWhole corpus (driver: #{Driver.name()})")
    scores |> Enum.sort() |> Enum.each(fn {key, value} -> IO.puts("  #{String.pad_trailing(key, 26)} #{value}") end)

    if System.get_env("CONFORMANCE_UPDATE") in ["1", "true"] do
      File.mkdir_p!(Path.dirname(scores_path()))
      File.write!(scores_path(), Jason.encode_to_iodata!(scores, pretty: true))
    else
      floors = scores_path() |> File.read!() |> Jason.decode!()

      for {key, floor} <- floors, key not in ["files", "files_with_operations", "requests"] do
        assert scores[key] >= floor * 0.99, "#{key} fell to #{scores[key]}, below the floor of #{floor}"
      end
    end
  end

  @tag :nightly
  test "a 10 MB reply decodes within budget" do
    row = "<row><id>123456</id><name>Some name value</name><amount>12.50</amount><flag>true</flag></row>"
    body = soap11("<r>" <> String.duplicate(row, div(10_000_000, byte_size(row))) <> "</r>")

    Harness.check(
      "nightly/large_reply",
      fn ->
        {micros, result} = :timer.tc(fn -> driver().decode(nil, nil, 200, [], body) end)
        assert {:ok, _} = result
        assert micros < 3_000_000, "took #{div(micros, 1000)} ms"
      end,
      timeout: 120_000
    )
  end
end
