defmodule Soap.Options do
  @moduledoc false

  # How call options combine with a client's defaults. Most options are replaced by the
  # call. These are merged instead:
  #
  #   * `:http_headers` - by name, ignoring case. The call's value wins, and a `nil`
  #     value removes the header.
  #   * `:soap_headers` - by name. The call's value wins, `nil` removes it, and unnamed
  #     ones such as `%Soap.Raw{}` are added.
  #   * `:http_opts` - by key, recursively for keyword lists such as `req: [...]`.
  #   * `:telemetry_metadata` - by key.

  @doc "Combines a client's options with a call's."
  @spec merge(keyword(), keyword()) :: keyword()
  def merge(defaults, overrides) do
    Keyword.merge(defaults, overrides, fn
      :http_headers, a, b -> merge_http_headers(a, b)
      :soap_headers, a, b -> merge_soap_headers(a, b)
      :http_opts, a, b -> deep_merge(a, b)
      :telemetry_metadata, a, b -> Map.merge(a, b)
      _key, _a, b -> b
    end)
  end

  @doc "Drops HTTP headers set to nil."
  @spec http_headers(list()) :: [{String.t(), String.t()}]
  def http_headers(headers), do: Enum.reject(headers, fn {_name, value} -> is_nil(value) end)

  @doc "SOAP headers as a list, with ones set to nil dropped."
  @spec soap_headers(map() | list()) :: list()
  def soap_headers(headers) when is_map(headers), do: headers |> Enum.to_list() |> soap_headers()
  def soap_headers(headers), do: Enum.reject(headers, &match?({_name, nil}, &1))

  defp merge_http_headers(a, b) do
    names = MapSet.new(b, fn {name, _} -> downcase(name) end)
    Enum.reject(a, fn {name, _} -> downcase(name) in names end) ++ b
  end

  defp merge_soap_headers(a, b) do
    b = to_list(b)
    names = for {name, _} <- b, into: MapSet.new(), do: key(name)

    Enum.reject(to_list(a), fn
      {name, _} -> key(name) in names
      _unnamed -> false
    end) ++ b
  end

  defp key(name) when is_atom(name), do: Atom.to_string(name)
  defp key(name), do: name

  defp to_list(headers) when is_map(headers), do: Enum.to_list(headers)
  defp to_list(headers), do: headers

  defp deep_merge(a, b) do
    if Keyword.keyword?(a) and Keyword.keyword?(b) do
      Keyword.merge(a, b, fn _key, x, y ->
        if Keyword.keyword?(x) and Keyword.keyword?(y), do: deep_merge(x, y), else: y
      end)
    else
      b
    end
  end

  defp downcase(name), do: name |> to_string() |> String.downcase()
end
