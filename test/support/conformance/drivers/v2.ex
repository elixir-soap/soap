defmodule Soap.Conformance.Drivers.V2 do
  @moduledoc """
  Drives the 2.0 modules through the conformance contract.

  So far only the WSDL model exists. Building requests, calling and decoding raise, so
  that checks expecting `{:error, _}` can't pass just because nothing is built yet.
  """
  @behaviour Soap.Conformance.Driver

  alias Soap.{Encoder, Service}

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

  defp encoder_opts(opts) do
    [headers: opts[:soap_headers] || []] ++ Keyword.take(opts, [:validate, :mtom])
  end

  # A list of nodes holding one scalar under no name means the element's own value.
  defp to_params(params), do: params

  defp with_adapter(opts) do
    [http: :persistent_term.get(@adapter_key, Soap.HTTP.HTTPoison)] ++ opts
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
    operation_opts = if opts[:soap_version], do: [version: opts[:soap_version]], else: []

    with {:ok, operation} <- Service.operation(service, name, operation_opts),
         {:ok, encoded} <- Encoder.encode(service, operation, to_params(params), encoder_opts(opts)) do
      {:ok, %{body: encoded.xml, headers: Soap.Request.headers(operation, opts[:http_headers] || [])}}
    end
  end

  @impl true
  def call(_service, _operation, _params, _opts), do: raise("not implemented")

  @impl true
  def decode(_service, _operation, _status, _headers, _body), do: raise("not implemented")

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
