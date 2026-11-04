defmodule Soap.Conformance.Drivers.V2 do
  @moduledoc """
  Drives the public API through the conformance contract.
  """
  @behaviour Soap.Conformance.Driver

  alias Soap.Service

  @adapter_key {__MODULE__, :adapter}

  defmodule Refuse do
    @moduledoc false
    @behaviour Soap.HTTP
    @key {__MODULE__, :attempts}

    def reset, do: :persistent_term.put(@key, :ets.new(:v2_attempts, [:public, :duplicate_bag]))
    def attempts, do: @key |> :persistent_term.get() |> :ets.tab2list() |> Enum.map(&elem(&1, 1))

    @impl true
    def request(_method, url, _headers, _body, _opts) do
      :ets.insert(:persistent_term.get(@key), {:attempt, url})
      {:error, :network_disabled}
    end
  end

  defp with_adapter(opts) do
    [http: :persistent_term.get(@adapter_key, Soap.HTTP.Req)] ++ opts
  end

  @impl true
  def load(path, opts), do: Service.load(path, with_adapter(opts))

  @impl true
  def load_string(wsdl, opts), do: Service.from_string(wsdl, with_adapter(opts))

  @impl true
  def load_url(url, opts), do: Service.load(url, with_adapter(opts))

  @impl true
  def operations(service), do: Service.operations(service)

  @impl true
  def endpoints(service), do: Service.endpoints(service)

  @impl true
  def schema_types(service) do
    service.schema.types |> Map.keys() |> Enum.map(fn {_ns, name} -> String.downcase(name) end)
  end

  @impl true
  def build_request(service, name, params, opts) do
    case Soap.build_request(client(service), name, params, call_opts(opts)) do
      {:ok, request} -> {:ok, %{body: request.body, headers: request.headers}}
      {:error, _} = error -> error
    end
  end

  @impl true
  def call(service, name, params, opts) do
    service |> client() |> Soap.call(name, params, call_opts(opts)) |> translate()
  end

  @impl true
  def decode(service, name, status, headers, body) do
    client = if service, do: client(service)

    case Soap.decode_response(client, name, status, headers, body) do
      {:ok, response} -> {:ok, response.result}
      error -> translate(error)
    end
  end

  defp client(service), do: Soap.new(service, http: :persistent_term.get(@adapter_key, Soap.HTTP.Req))

  defp call_opts(opts) do
    Enum.flat_map(opts, fn
      {:soap_version, version} -> [version: version]
      {:soap_headers, nil} -> []
      {:soap_headers, headers} -> [headers: headers]
      {:recv_timeout, value} -> [timeout: value]
      {:timeout, value} -> [connect_timeout: value]
      other -> [other]
    end)
  end

  defp translate({:ok, result}), do: {:ok, result}
  defp translate({:error, %Soap.Fault{code: code, message: message}}), do: {:fault, %{code: code, message: message}}
  defp translate({:error, %Soap.Error{reason: reason}}), do: {:error, reason}

  @impl true
  def without_network(fun) do
    Refuse.reset()
    :persistent_term.put(@adapter_key, Refuse)

    try do
      result = fun.()
      {result, Refuse.attempts()}
    after
      :persistent_term.erase(@adapter_key)
    end
  end

  @impl true
  def with_network(fun) do
    {:ok, _} = Application.ensure_all_started(:req)
    fun.()
  end

  # 2.0 reads no application configuration at all, so there is nothing to remove.
  @impl true
  def without_app_config(fun), do: fun.()

  @impl true
  def tolerant_opts(_versions), do: [ignore_failed_imports: true]
end
