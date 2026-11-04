[live_dir, out] = System.argv()
:logger.set_primary_config(:level, :none)
{:ok, _} = Application.ensure_all_started(:hackney)
Application.put_env(:soap, :globals, version: "1.1", http_client: HTTPoison)

# name, wsdl dir, operation, params, opts, recorded raw status from the hand-built request
cases = [
  {"calculator-add-11", "001", "Add", %{intA: 2, intB: 3}, []},
  {"calculator-add-12", "001", "Add", %{intA: 2, intB: 3}, [soap_version: "1.2"]},
  {"calculator-divzero-11", "001", "Divide", %{intA: 1, intB: 0}, []},
  {"tempconvert-11", "002", "CelsiusToFahrenheit", %{Celsius: "20"}, []},
  {"numberconversion-11", "003", "NumberToWords", %{ubiNum: 500}, []},
  {"country-capital", "004", "CapitalCity", %{sCountryISOCode: "FR"}, []},
  {"country-continents-array", "004", "ListOfContinentsByName", %{}, []},
  {"crcind-add", "005", "AddInteger", %{Arg1: 2, Arg2: 3}, []},
  {"crcind-dataset", "005", "GetDataSetByName", %{name: "A"}, []},
  {"vies-invalid", "006", "checkVat", %{countryCode: "DE", vatNumber: "000000000"}, []},
  {"bcb-rpc-encoded-multiref", "053", "getUltimoValorVO", %{in0: 1}, []},
  {"smartbear-array", "018", "GetArray", %{}, []},
  {"cbr-datetime", "035", "GetLatestDateTime", %{}, []},
  {"cbr-diffgram", "035", "EnumValutes", %{Seld: "false"}, []},
  {"arcgis-defaultmap", "036", "GetDefaultMapName", %{}, []},
  {"swiss-uid-validate", "041", "ValidateVatNumber", %{vatNumber: "CHE-116.281.710"}, []},
  {"ebi-parameters", "058", "getParameters", %{}, []},
  {"herong-hello", "013", "Hello", "World", []},
  {"eori-invalid", "009", "validateEORI", %{eori: "DE000000000"}, []}
]

guard = fn fun ->
  {pid, ref} = spawn_monitor(fn -> exit({:res, fun.()}) end)

  receive do
    {:DOWN, ^ref, _, _, {:res, r}} -> r
    {:DOWN, ^ref, _, _, {%{__struct__: s}, _}} -> {:crash, inspect(s)}
    {:DOWN, ^ref, _, _, {{k, _}, _}} -> {:crash, inspect(k)}
    {:DOWN, ^ref, _, _, {k, _}} -> {:crash, inspect(k) |> String.slice(0, 50)}
    {:DOWN, ^ref, _, _, o} -> {:crash, inspect(o) |> String.slice(0, 50)}
  after
    40_000 ->
      Process.exit(pid, :kill)
      {:crash, "timeout"}
  end
end

results =
  for {name, d, op, params, opts} <- cases do
    wsdl_path = Path.join([live_dir, d, "body"])

    r =
      guard.(fn ->
        {:ok, m} = Soap.Wsdl.parse(File.read!(wsdl_path), wsdl_path, [skip_type_imports: true, allow_empty_soap_actions: true] ++ opts)

        case Soap.call(m, op, params, [], recv_timeout: 25_000, timeout: 15_000) do
          {:ok, resp} ->
            parsed = guard.(fn -> Soap.Response.parse(resp) end)
            %{http: resp.status_code, fault: String.contains?(resp.body, "Fault>"), parsed: inspect(parsed, limit: 6, printable_limit: 70) |> String.slice(0, 120), body: resp.body}

          {:error, e} ->
            %{transport_error: inspect(e)}
        end
      end)

    line =
      case r do
        %{http: h} -> "#{h} fault=#{r.fault} #{r.parsed}"
        %{transport_error: e} -> "transport-error #{e}"
        {:crash, k} -> "CRASH before reply: #{k}"
      end

    IO.puts(String.pad_trailing(name, 28) <> line)
    Process.sleep(400)
    {name, is_map(r) && Map.get(r, :http), inspect(r) |> String.slice(0, 300)}
  end

File.write!(out, inspect(results, limit: :infinity, printable_limit: :infinity))
