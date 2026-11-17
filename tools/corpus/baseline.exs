[corpus, expected_path, out_path] = System.argv()
:logger.set_primary_config(:level, :none)
Application.put_env(:soap, :globals, version: "1.1", http_client: HTTPoison)

defmodule B do
  def guarded(fun, timeout) do
    {pid, ref} = spawn_monitor(fn -> exit({:result, fun.()}) end)

    receive do
      {:DOWN, ^ref, _, _, {:result, r}} -> r
      {:DOWN, ^ref, _, _, reason} -> {:crash, kind(reason)}
    after
      timeout ->
        Process.exit(pid, :kill)
        {:crash, "timeout"}
    end
  end

  defp kind({%{__struct__: s}, _}), do: inspect(s)
  defp kind({{:badmatch, _}, _}), do: "MatchError"
  defp kind({:badarg, _}), do: "ArgumentError"
  defp kind({:function_clause, _}), do: "FunctionClauseError"
  defp kind({{:badmap, _}, _}), do: "BadMapError"
  defp kind({:fatal, _}), do: "xmerl-exit"
  defp kind({k, _}) when is_atom(k), do: to_string(k)
  defp kind({{k, _}, _}) when is_atom(k), do: to_string(k)
  defp kind(o), do: String.slice(inspect(o), 0, 40)

  def parse(path, doc, opts) do
    guarded(fn -> {:ok, m} = Soap.Wsdl.parse(doc, path, [skip_type_imports: true] ++ opts); m end, 20_000)
  end

  def wellformed?(xml) when is_binary(xml) do
    try do
      {_, _} = :xmerl_scan.string(String.to_charlist(xml), quiet: true)
      not String.contains?(xml, "xmlns:=")
    catch
      _, _ -> false
    end
  end

  def wellformed?(_), do: false
end

entries = expected_path |> File.read!() |> Jason.decode!()
out = File.open!(out_path, [:write, :utf8])

for e <- entries do
  path = Path.join(corpus, e["path"])
  doc = File.read!(path)
  expected_any = Enum.uniq(e["ops11"] ++ e["ops12"])
  v12only = e["ops11"] == [] and e["ops12"] != []
  m_default = B.parse(path, doc, [])
  m_loose = B.parse(path, doc, allow_empty_soap_actions: true, soap_version: if(v12only, do: "1.2", else: "1.1"))

  names = fn
    %{operations: ops} -> ops |> Enum.map(& &1.name) |> Enum.uniq()
    _ -> nil
  end

  body_stats =
    case m_loose do
      %{operations: ops} ->
        ops
        |> Enum.map(& &1.name)
        |> Enum.uniq()
        |> Enum.take(8)
        |> Enum.map(fn op ->
          r = B.guarded(fn -> Soap.Request.Params.build_body(m_loose, op, %{}, %{}) end, 5_000)
          want = get_in(e, ["wrappers", op, "expect"])

          case r do
            {:crash, k} -> %{op: op, build: "crash", kind: k}
            xml when is_binary(xml) ->
              got = case Regex.run(~r/<env:Body><([^\s>\/]+)/, xml) do
                [_, g] -> g |> String.split(":") |> List.last()
                _ -> nil
              end
              %{op: op, build: "ok", wellformed: B.wellformed?(xml), wrapper_ok: want == nil or got == want, want: want, got: got}
            other -> %{op: op, build: "error-as-body", kind: String.slice(inspect(other), 0, 60)}
          end
        end)
      _ -> []
    end

  rec = %{
    path: e["path"],
    expected_ops: length(expected_any),
    own_ops: e["own_ops"],
    default: case m_default do %{} -> %{ok: true, ops: length(names.(m_default)), endpoint: m_default.endpoint != ""}; {:crash, k} -> %{ok: false, crash: k} end,
    loose: case m_loose do %{} -> %{ok: true, ops: length(names.(m_loose)), endpoint: m_loose.endpoint != ""}; {:crash, k} -> %{ok: false, crash: k} end,
    bodies: body_stats,
    features: e["features"]
  }

  IO.puts(out, Jason.encode!(rec))
end

File.close(out)
IO.puts("done #{length(entries)}")
