defmodule Soap.Service.Loader do
  @moduledoc """
  Reads a WSDL and everything it imports, under rules that keep a hostile document from
  reaching anything it shouldn't.

  ## What gets followed

  | Reference found in a document | From a local file | From a URL |
  |---|---|---|
  | Relative path | Read, inside `:import_root` if set | Fetched from the same host |
  | `http` or `https` URL | Skipped unless the host is allowed | Fetched if the host is the same or allowed |
  | Absolute path, `file:`, other schemes | Skipped | Skipped |

  Allow more hosts with `allow_imports_from: ["host"]`, or every host with `:all`.

  Skipped imports don't fail the load. They appear in `unresolved_imports`, with the
  reason. An import the rules allow but that can't be read is an error, because the
  model would be silently incomplete. To accept a partial model anyway, pass
  `ignore_failed_imports: true`, and those imports are listed as `:import_failed`.
  """

  alias Soap.{HTTP, Schema, XML}
  alias Soap.XML.Element

  @wsdl "http://schemas.xmlsoap.org/wsdl/"
  @wsdl2 "http://www.w3.org/ns/wsdl"
  @xsd "http://www.w3.org/2001/XMLSchema"

  @max_documents 1_000
  @max_bytes 200_000_000

  defstruct opts: [], visited: MapSet.new(), wsdls: [], schema: %Schema{}, unresolved: [], documents: 0, bytes: 0

  @type result :: %{wsdls: [Element.t()], schema: Schema.t(), unresolved_imports: [{String.t(), atom()}]}

  @doc "Loads from a file path or an `http` or `https` URL."
  @spec load(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def load(source, opts) do
    location = if url?(source), do: {:url, source}, else: {:file, Path.expand(source)}

    with {:ok, body} <- read(location, opts) do
      load_document(body, location, opts)
    end
  end

  @doc "Loads from a string. `:base` is a path or URL that relative imports resolve against."
  @spec load_string(binary(), keyword()) :: {:ok, result()} | {:error, term()}
  def load_string(wsdl, opts) do
    location =
      case opts[:base] do
        nil -> :inline
        base -> if url?(base), do: {:url, base}, else: {:file, Path.expand(base)}
      end

    load_document(wsdl, location, opts)
  end

  defp load_document(body, location, opts) do
    state = %__MODULE__{opts: opts, visited: MapSet.new([location_key(location, nil)])}

    with {:ok, root} <- XML.parse(body, unknown_encoding: :latin1),
         :ok <- check_root(root),
         {:ok, state} <- walk(root, location, nil, count(state, body)) do
      {:ok,
       %{wsdls: Enum.reverse(state.wsdls), schema: state.schema, unresolved_imports: Enum.reverse(state.unresolved)}}
    end
  end

  defp check_root(%Element{ns: ns, name: "definitions"}) when ns in [@wsdl, nil], do: :ok
  defp check_root(%Element{ns: @xsd, name: "schema"}), do: :ok
  defp check_root(%Element{ns: @wsdl2, name: "description"}), do: {:error, {:unsupported, :wsdl_2_0}}
  defp check_root(%Element{name: name}), do: {:error, {:not_a_wsdl, name}}

  # Documents

  defp walk(%Element{ns: @xsd, name: "schema"} = schema, location, target, state) do
    walk_schema(schema, location, target, state)
  end

  defp walk(%Element{name: "definitions"} = definitions, location, _target, state) do
    with {:ok, state} <- walk_wsdl_imports(definitions, location, state),
         {:ok, state} <- walk_inline_schemas(definitions, location, state) do
      {:ok, %{state | wsdls: [definitions | state.wsdls]}}
    end
  end

  defp walk(%Element{name: name}, location, _target, _state) do
    {:error, {:import_failed, describe(location), {:not_a_wsdl_or_schema, name}}}
  end

  defp walk_wsdl_imports(definitions, location, state) do
    definitions.children
    |> Enum.filter(&(&1.name == "import" and &1.ns in [@wsdl, nil]))
    |> reduce(state, &follow(Element.attr(&1, "location"), location, nil, &2))
  end

  defp walk_inline_schemas(definitions, location, state) do
    definitions.children
    |> Enum.filter(&(&1.name == "types"))
    |> Enum.flat_map(&Element.children(&1, @xsd, "schema"))
    |> reduce(state, &walk_schema(&1, location, nil, &2))
  end

  defp walk_schema(schema, location, target, state) do
    effective = Element.attr(schema, "targetNamespace") || target

    with {:ok, state} <- walk_schema_references(schema, location, effective, state) do
      read = Schema.read(schema, target_namespace: target)
      {:ok, %{state | schema: Schema.merge(state.schema, read)}}
    end
  end

  # An imported schema has its own namespace. An included one takes on this one's.
  defp walk_schema_references(schema, location, target, state) do
    schema.children
    |> Enum.filter(&(&1.ns == @xsd and &1.name in ["import", "include", "redefine"]))
    |> reduce(state, fn reference, acc ->
      inherited = if reference.name == "import", do: nil, else: target
      follow(Element.attr(reference, "schemaLocation"), location, inherited, acc)
    end)
  end

  defp reduce(items, state, fun) do
    Enum.reduce_while(items, {:ok, state}, fn item, {:ok, acc} ->
      case fun.(item, acc) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  # Following a reference

  defp follow(nil, _base, _target, state), do: {:ok, state}

  defp follow(reference, base, target, state) do
    case String.trim(reference) do
      "" -> {:ok, state}
      trimmed -> trimmed |> resolve(base, state.opts) |> follow_resolved(trimmed, target, state)
    end
  end

  defp follow_resolved({:blocked, reason}, reference, _target, state) do
    {:ok, %{state | unresolved: [{reference, reason} | state.unresolved]}}
  end

  defp follow_resolved({:ok, location}, reference, target, state) do
    key = location_key(location, target)

    cond do
      MapSet.member?(state.visited, key) ->
        {:ok, state}

      state.documents >= @max_documents ->
        {:error, :too_many_documents}

      true ->
        location |> visit(target, %{state | visited: MapSet.put(state.visited, key)}) |> tolerate(reference, state)
    end
  end

  defp tolerate({:error, {:import_failed, _, _}} = error, reference, state) do
    if state.opts[:ignore_failed_imports] do
      {:ok, %{state | unresolved: [{reference, :import_failed} | state.unresolved]}}
    else
      error
    end
  end

  defp tolerate(result, _reference, _state), do: result

  defp visit(location, target, state) do
    with {:ok, body} <- read(location, state.opts),
         state = count(state, body),
         :ok <- check_size(state),
         {:ok, root} <- parse_import(body, location) do
      walk(root, location, target, state)
    else
      {:error, {:import_failed, _, _}} = error -> error
      {:error, :too_much_data} = error -> error
      {:error, reason} -> {:error, {:import_failed, describe(location), reason}}
    end
  end

  defp parse_import(body, location) do
    case XML.parse(body, unknown_encoding: :latin1) do
      {:ok, root} -> {:ok, root}
      {:error, reason} -> {:error, {:import_failed, describe(location), reason}}
    end
  end

  defp count(state, body), do: %{state | documents: state.documents + 1, bytes: state.bytes + byte_size(body)}

  defp check_size(%{bytes: bytes}) when bytes > @max_bytes, do: {:error, :too_much_data}
  defp check_size(_state), do: :ok

  # Rules

  defp resolve(reference, base, opts) do
    case URI.parse(reference).scheme do
      nil -> resolve_relative(reference, base, opts)
      scheme when scheme in ["http", "https"] -> resolve_url(reference, base, opts)
      _ -> {:blocked, :scheme_not_allowed}
    end
  end

  defp resolve_relative(_reference, :inline, _opts), do: {:blocked, :no_base_location}

  defp resolve_relative(reference, {:url, base}, _opts) do
    {:ok, {:url, base |> URI.merge(reference) |> URI.to_string()}}
  end

  defp resolve_relative(reference, {:file, base}, opts) do
    path = reference |> String.split("?") |> hd()

    if Path.type(path) == :absolute do
      {:blocked, :absolute_path}
    else
      path |> Path.expand(Path.dirname(base)) |> check_root_directory(opts[:import_root])
    end
  end

  defp check_root_directory(path, nil), do: {:ok, {:file, path}}

  defp check_root_directory(path, root) do
    root = Path.expand(root)
    if String.starts_with?(path, root <> "/"), do: {:ok, {:file, path}}, else: {:blocked, :outside_import_root}
  end

  defp resolve_url(reference, base, opts) do
    if allowed_host?(URI.parse(reference).host, base, opts[:allow_imports_from]) do
      {:ok, {:url, reference}}
    else
      {:blocked, :host_not_allowed}
    end
  end

  defp allowed_host?(_host, _base, :all), do: true
  defp allowed_host?(host, {:url, base}, allowed), do: host == URI.parse(base).host or host in List.wrap(allowed)
  defp allowed_host?(host, _base, allowed), do: host in List.wrap(allowed)

  # Reading

  defp read({:file, path}, _opts) do
    case File.read(path) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, {:file, reason, path}}
    end
  end

  defp read({:url, url}, opts) do
    case HTTP.adapter(opts).request(:get, url, [], "", Keyword.get(opts, :http_opts, follow_redirect: true)) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_status, status, url}}
      {:error, reason} -> {:error, {:http, reason, url}}
    end
  end

  defp location_key(location, target), do: {location, target}

  defp describe({_kind, value}), do: value
  defp describe(:inline), do: "inline"

  defp url?(source), do: String.starts_with?(source, ["http://", "https://"])
end
