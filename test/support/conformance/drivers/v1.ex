defmodule Soap.Conformance.Drivers.V1 do
  @moduledoc """
  Drives the current `Soap` 1.x API through the conformance contract.

  This driver reports what 1.x does. It adds no error handling of its own, so its
  crashes show up as failed checks.
  """
  @behaviour Soap.Conformance.Driver

  defmodule NoNetwork do
    @moduledoc false
    @key :soap_conformance_attempts

    def reset, do: :persistent_term.put(@key, :ets.new(:attempts, [:public, :duplicate_bag]))
    def attempts, do: @key |> :persistent_term.get() |> :ets.tab2list() |> Enum.map(&elem(&1, 1))

    defp record(url) do
      :ets.insert(:persistent_term.get(@key), {:attempt, url})
      {:error, %HTTPoison.Error{reason: :network_disabled}}
    end

    def get(url, _headers, _opts), do: record(url)

    def get!(url, _headers, _opts) do
      record(url)
      raise %HTTPoison.Error{reason: :network_disabled}
    end

    def post(url, _body, _headers, _opts), do: record(url)
  end

  @impl true
  def load(path, opts), do: Soap.init_model(path, :file, opts)

  @impl true
  def load_string(wsdl, opts), do: Soap.Wsdl.parse(wsdl, "inline.wsdl", opts)

  @impl true
  def load_url(url, opts), do: Soap.init_model(url, :url, opts)

  @impl true
  def operations(model), do: model.operations |> Enum.map(& &1.name) |> Enum.uniq()

  @impl true
  def endpoints(%{endpoint: ""}), do: []
  def endpoints(%{endpoint: endpoint}), do: [endpoint]

  @impl true
  def schema_types(model), do: model.validation_types |> Map.keys() |> Enum.map(&String.downcase/1)

  @impl true
  def tolerant_opts(versions) do
    version = if "1.1" in versions or versions == [], do: "1.1", else: "1.2"
    [allow_empty_soap_actions: true, soap_version: version]
  end

  @impl true
  def build_request(model, operation, params, opts) do
    {soap_headers, params} = split_headers(params, opts)
    headers = Soap.Request.Headers.build(model, operation, opts[:http_headers] || [])
    {:ok, %{body: Soap.Request.Params.build_body(model, operation, to_v1(params), soap_headers), headers: headers}}
  end

  @impl true
  def call(model, operation, params, opts) do
    {soap_headers, params} = split_headers(params, opts)
    model = if opts[:endpoint], do: %{model | endpoint: opts[:endpoint]}, else: model
    http_opts = Keyword.take(opts, [:recv_timeout, :timeout, :follow_redirect])

    case Soap.call(model, operation, {soap_headers, to_v1(params)}, opts[:http_headers] || [], http_opts) do
      {:ok, %Soap.Response{status_code: status, headers: headers, body: body}} ->
        decode(model, operation, status, headers, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def decode(_model, _operation, status, _headers, body) do
    parsed = Soap.Response.parse(body, status)

    # 1.x has no notion of a Fault. It returns the Fault's children as a plain map
    # when the status is 400 or above, and that is the only form it can report.
    case parsed do
      %{faultcode: code, faultstring: message} when status >= 400 ->
        {:fault, %{code: text(code), message: text(message)}}

      other ->
        {:ok, other}
    end
  end

  @impl true
  def without_network(fun) do
    saved = Application.get_env(:soap, :globals)
    NoNetwork.reset()
    Application.put_env(:soap, :globals, Keyword.put(saved, :http_client, NoNetwork))

    try do
      result = fun.()
      {result, NoNetwork.attempts()}
    after
      Application.put_env(:soap, :globals, saved)
    end
  end

  @impl true
  def with_network(fun) do
    {:ok, _} = Application.ensure_all_started(:hackney)
    fun.()
  end

  @impl true
  def without_app_config(fun) do
    saved = Application.get_env(:soap, :globals)
    Application.delete_env(:soap, :globals)

    try do
      fun.()
    after
      Application.put_env(:soap, :globals, saved)
    end
  end

  defp split_headers(params, opts), do: {to_header_map(opts[:soap_headers]), params}

  defp to_header_map(nil), do: %{}
  defp to_header_map(headers), do: Map.new(headers)

  defp to_v1(params) when is_list(params) do
    Enum.map(params, fn {name, attrs, value} -> {name, attrs, to_v1(value)} end)
  end

  defp to_v1(value), do: value

  defp text(value) when is_binary(value), do: value
  defp text(%{"_value" => value}), do: text(value)
  defp text(value), do: inspect(value)
end
