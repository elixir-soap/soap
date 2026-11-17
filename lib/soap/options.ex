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
      :http_headers, a, b when is_list(a) and is_list(b) -> merge_http_headers(a, b)
      :soap_headers, a, b when (is_list(a) or is_map(a)) and (is_list(b) or is_map(b)) -> merge_soap_headers(a, b)
      :http_opts, a, b -> deep_merge(a, b)
      :telemetry_metadata, a, b when is_map(a) and is_map(b) -> Map.merge(a, b)
      _key, _a, b -> b
    end)
  end

  @doc """
  Checks the shape of the options that are used before anything is sent. Returns
  `{:error, {:invalid_option, key, reason}}` for the first one that's wrong.
  """
  @spec validate(keyword()) :: :ok | {:error, {:invalid_option, atom(), String.t()}}
  def validate(opts) do
    Enum.find_value(opts, :ok, fn {key, value} ->
      case check(key, value) do
        :ok -> nil
        {:error, reason} -> {:error, {:invalid_option, key, reason}}
      end
    end)
  end

  defp check(:http_headers, headers) do
    if is_list(headers) and Enum.all?(headers, &header?/1),
      do: :ok,
      else: {:error, "must be a list of {name, value} string pairs"}
  end

  defp check(:soap_headers, headers) when is_map(headers) or is_list(headers), do: :ok
  defp check(:soap_headers, _), do: {:error, "must be a map or a list"}

  defp check(:attachments, attachments) do
    if is_list(attachments) and Enum.all?(attachments, &match?(%Soap.Attachment{data: data} when is_binary(data), &1)),
      do: :ok,
      else: {:error, "must be a list of %Soap.Attachment{} with binary data"}
  end

  defp check(:http_opts, opts) when is_list(opts), do: :ok
  defp check(:http_opts, _), do: {:error, "must be a keyword list"}
  defp check(:telemetry_metadata, meta) when is_map(meta), do: :ok
  defp check(:telemetry_metadata, _), do: {:error, "must be a map"}
  defp check(:endpoint, url) when is_nil(url) or is_binary(url), do: :ok
  defp check(:endpoint, _), do: {:error, "must be a string"}
  defp check(:port, name) when is_nil(name) or is_binary(name), do: :ok
  defp check(:port, _), do: {:error, "must be a string"}
  defp check(:version, version) when version in [nil, "1.1", "1.2"], do: :ok
  defp check(:version, _), do: {:error, ~s(must be "1.1" or "1.2")}
  defp check(key, value) when key in [:timeout, :connect_timeout] and is_integer(value) and value >= 0, do: :ok
  defp check(key, _) when key in [:timeout, :connect_timeout], do: {:error, "must be a non-negative integer"}

  defp check(:max_reply_size, size) when size == :infinity or (is_integer(size) and size > 0), do: :ok
  defp check(:max_reply_size, _), do: {:error, "must be a positive integer or :infinity"}
  defp check(:http, module) when is_atom(module), do: :ok
  defp check(:http, _), do: {:error, "must be a module"}
  defp check(_key, _value), do: :ok

  defp header?({name, value}) when is_binary(name) or is_atom(name), do: is_binary(value) or is_nil(value)
  defp header?(_), do: false

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
    if Keyword.keyword?(a) and Keyword.keyword?(b),
      do: Keyword.merge(a, b, fn _key, x, y -> deep_merge(x, y) end),
      else: b
  end

  defp downcase(name), do: name |> to_string() |> String.downcase()
end
