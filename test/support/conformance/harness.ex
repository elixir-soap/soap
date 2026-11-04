defmodule Soap.Conformance.Harness do
  @moduledoc """
  Runs conformance checks with a ratchet.

  Every check has a stable id. The file `test/corpus/known_failures/<driver>.json`
  lists the checks that driver is known to fail:

    * Passing and not listed: the test passes.
    * Failing and listed: the test passes, and counts as a known failure.
    * Failing and not listed: the test fails. This is a regression or a new gap.
    * Passing and listed: the test fails until the entry is removed, so progress
      is locked in as soon as it happens.

  To rewrite the file after a deliberate change:

      CONFORMANCE_UPDATE=1 mix test
  """

  @table :soap_conformance_results
  @known_dir Path.expand("../../corpus/known_failures", __DIR__)

  def start do
    :ets.new(@table, [:named_table, :public, :set])
    :persistent_term.put({__MODULE__, :known}, read_known())
    ExUnit.after_suite(&finish/1)
    :ok
  end

  @doc "Runs `fun` as check `id`. Any raise, throw, exit or timeout counts as a failure."
  def check(id, fun, opts \\ []) do
    outcome = isolate(fun, Keyword.get(opts, :timeout, 20_000))
    known = :persistent_term.get({__MODULE__, :known})
    listed? = Map.has_key?(known, id)
    :ets.insert(@table, {id, outcome})

    cond do
      updating?() -> :ok
      outcome == :pass and listed? -> ExUnit.Assertions.flunk(xpass_message(id))
      outcome == :pass -> :ok
      listed? -> :ok
      true -> ExUnit.Assertions.flunk("#{id}\n#{elem(outcome, 1)}\n\nThis is a new failure. #{update_hint()}")
    end
  end

  defp isolate(fun, timeout) do
    parent = self()
    ref = make_ref()

    {pid, monitor} =
      spawn_monitor(fn ->
        result =
          try do
            fun.()
            :pass
          rescue
            e -> {:fail, describe(e)}
          catch
            kind, value -> {:fail, "#{kind}: #{clip(inspect(value))}"}
          end

        send(parent, {ref, result})
      end)

    receive do
      {^ref, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, _, _, reason} ->
        {:fail, "process died: #{clip(inspect(reason))}"}
    after
      timeout ->
        Process.exit(pid, :kill)
        Process.demonitor(monitor, [:flush])
        {:fail, "timeout after #{timeout} ms"}
    end
  end

  defp describe(%ExUnit.AssertionError{message: message}), do: clip(message)
  defp describe(%{__struct__: struct} = e), do: clip("#{inspect(struct)}: #{Exception.message(e)}")

  defp clip(text) do
    text
    |> String.replace(~r/#(PID|Port|Reference)<[^>]*>/, "#\\1")
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 180)
  end

  defp xpass_message(id) do
    "#{id}\nThis check now passes, but it is still listed as a known failure. #{update_hint()}"
  end

  defp update_hint do
    "If this is intended, run: CONFORMANCE_UPDATE=1 mix test"
  end

  defp updating?, do: System.get_env("CONFORMANCE_UPDATE") in ["1", "true"]

  defp known_path, do: Path.join(@known_dir, "#{Soap.Conformance.Driver.name()}.json")

  defp read_known do
    case File.read(known_path()) do
      {:ok, json} -> Jason.decode!(json)
      {:error, :enoent} -> %{}
    end
  end

  defp finish(_results) do
    rows = :ets.tab2list(@table)

    unless rows == [] do
      report(rows)
      if updating?(), do: write_known(rows)
    end
  end

  defp report(rows) do
    known = :persistent_term.get({__MODULE__, :known})

    summary =
      rows
      |> Enum.group_by(fn {id, _} -> id |> String.split("/") |> hd() end)
      |> Enum.sort()
      |> Enum.map_join("\n", fn {layer, checks} ->
        passing = Enum.count(checks, fn {_, outcome} -> outcome == :pass end)
        total = length(checks)
        percent = round(passing * 100 / total)
        "  #{String.pad_trailing(layer, 12)} #{pad(passing)} of #{pad(total)} passing (#{percent}%)"
      end)

    passing = Enum.count(rows, fn {_, outcome} -> outcome == :pass end)
    listed = Enum.count(rows, fn {id, _} -> Map.has_key?(known, id) end)

    IO.puts("""

    Conformance (driver: #{Soap.Conformance.Driver.name()})
    #{summary}
      #{String.pad_trailing("total", 12)} #{pad(passing)} of #{pad(length(rows))} passing, #{listed} listed as known failures
    """)
  end

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(4)

  defp write_known(rows) do
    ran = MapSet.new(rows, &elem(&1, 0))
    kept = :persistent_term.get({__MODULE__, :known}) |> Enum.reject(fn {id, _} -> id in ran end) |> Map.new()
    failing = for {id, {:fail, reason}} <- rows, into: %{}, do: {id, reason}
    merged = Map.merge(kept, failing)

    File.mkdir_p!(@known_dir)
    File.write!(known_path(), encode_sorted(merged))
    IO.puts("Wrote #{map_size(merged)} known failures to #{Path.relative_to_cwd(known_path())}")
  end

  defp encode_sorted(map) do
    lines =
      map
      |> Enum.sort()
      |> Enum.map_join(",\n", fn {id, reason} -> "  #{Jason.encode!(id)}: #{Jason.encode!(reason)}" end)

    "{\n#{lines}\n}\n"
  end
end
