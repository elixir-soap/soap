defmodule Soap.Conformance.LiveTest do
  @moduledoc """
  Live layer: read-only calls to public services, from `test/corpus/live_calls.json`.

  These services change and go down, so CI runs this layer on a schedule and it never
  blocks a merge. Keep to one call per case.

      mix test --only live
  """
  use ExUnit.Case

  import Soap.Conformance.Support

  alias Soap.Conformance.{Driver, Harness}

  @moduletag :live
  @moduletag capture_log: true
  @external_resource corpus_path("live_calls.json")

  defp driver, do: Driver.current()

  for call <- "live_calls.json" |> corpus_path() |> File.read!() |> Jason.decode!() do
    @call call
    @tag :live
    test "#{call["name"]}" do
      Harness.check(
        "live/#{@call["name"]}",
        fn ->
          result =
            driver().with_network(fn ->
              assert {:ok, model} = driver().load_url(@call["wsdl"], driver().tolerant_opts([@call["version"]]))
              params = Enum.map(@call["params"], fn [name, value] -> {name, %{}, value} end)
              endpoint = if @call["endpoint"], do: [endpoint: @call["endpoint"]], else: []
              driver().call(model, @call["operation"], params, [recv_timeout: 25_000, timeout: 15_000] ++ endpoint)
            end)

          case @call["expect"] do
            %{"fault" => code} ->
              assert {:fault, %{code: got}} = result
              assert String.contains?(got, code)

            %{"key" => key, "value" => wanted} ->
              assert {:ok, decoded} = result
              assert decoded |> values_at(key) |> leaves() |> Enum.any?(&String.contains?(&1, wanted))
          end
        end,
        timeout: 60_000
      )
    end
  end
end
