defmodule Soap.Conformance.ReplayTest do
  @moduledoc """
  Replay layer: real replies recorded from public services, decoded offline.

  No WSDL is used here, so a client must be able to report Faults and decode these
  replies without one.
  """
  use ExUnit.Case

  alias Soap.Conformance.{Driver, Harness, Support}

  @moduletag capture_log: true
  @external_resource Support.corpus_path("recordings/index.json")

  # What each recording must decode to:
  # {:value, key, text}, {:fault, text in code}, or :error.
  @expected %{
    "calculator-add-11" => {:value, "AddResult", "5"},
    "calculator-add-12" => {:value, "AddResult", "5"},
    "calculator-divzero-11" => {:fault, "Server"},
    "calculator-divzero-12" => {:fault, "Receiver"},
    "tempconvert-11" => {:value, "CelsiusToFahrenheitResult", "68"},
    "numberconversion-11" => {:value, "NumberToWordsResult", "five hundred"},
    "numberconversion-12" => {:value, "NumberToWordsResult", "five hundred"},
    "country-capital" => {:value, "CapitalCityResult", "Paris"},
    "country-continents-array" => {:value, "sName", "Europe"},
    "crcind-add" => {:value, "AddIntegerResult", "5"},
    "crcind-divzero" => :error,
    "crcind-dataset" => {:value, "GetDataSetByNameResult", nil},
    "crcind-person" => {:value, "City", "Pueblo"},
    "vies-invalid" => {:value, "valid", "false"},
    "ndfd-rpc-encoded" => :error,
    "bcb-rpc-encoded-multiref" => {:value, "getUltimoValorVOReturn", nil},
    "smartbear-array" => {:value, "int", "9"},
    "smartbear-object" => {:value, "Name", "TestComplete Sample"},
    "cbr-datetime" => {:value, "GetLatestDateTimeResult", "2026-11-04T00:00:00"},
    "cbr-diffgram" => {:value, "EnumValutesResult", nil},
    "arcgis-defaultmap" => {:value, "Result", "Layers"},
    "swiss-uid-validate" => {:value, "ValidateVatNumberResult", "true"},
    "ebi-parameters" => {:value, "id", "guidetreeout"},
    "herong-hello" => {:value, "HelloResponse", "Hello from server"},
    "eori-invalid" => {:fault, "Client"},
    "badaction-calculator" => {:fault, "Client"},
    "malformed-envelope-calculator" => :error
  }

  defp decode(name, status, content_type) do
    body = "recordings/#{name}/response.body" |> Support.corpus_path() |> File.read!()
    Driver.current().decode(nil, nil, status, [{"Content-Type", content_type}], body)
  end

  defp assert_expected(result, {:value, key, wanted}) do
    assert {:ok, decoded} = result
    values = Support.values_at(decoded, key)
    assert values != [], "no #{key} in result"

    if wanted do
      assert Enum.any?(Support.leaves(values), &String.contains?(&1, wanted)), "no #{wanted} under #{key}"
    end
  end

  defp assert_expected(result, {:fault, code}) do
    assert {:fault, %{code: got, message: message}} = result
    assert String.contains?(got, code)
    assert is_binary(message) and message != ""
  end

  defp assert_expected(result, :error), do: assert({:error, _} = result)

  cases = "recordings/index.json" |> Support.corpus_path() |> File.read!() |> Jason.decode!() |> Map.fetch!("cases")

  for %{"name" => name, "status" => status, "content_type" => content_type} <- cases do
    @name name
    @status String.to_integer(status)
    @content_type content_type

    test "#{name} decodes as expected" do
      Harness.check("replay/#{@name}/result", fn ->
        assert_expected(decode(@name, @status, @content_type), Map.fetch!(@expected, @name))
      end)
    end

    if match?({:value, _, _}, Map.fetch!(@expected, name)) do
      test "#{name} has clean keys" do
        Harness.check("replay/#{@name}/clean_keys", fn ->
          assert {:ok, decoded} = decode(@name, @status, @content_type)
          dirty = decoded |> Support.keys() |> Enum.filter(&(String.contains?(&1, ":") or &1 == "xmlns"))
          assert dirty == []
        end)
      end
    end
  end
end
