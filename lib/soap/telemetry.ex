defmodule Soap.Telemetry do
  @moduledoc """
  Telemetry events for SOAP calls.

  Each call runs inside a `:telemetry.span/3`, which emits:

    * `[:soap, :request, :start]`
    * `[:soap, :request, :stop]`
    * `[:soap, :request, :exception]`

  Metadata holds `:operation`, `:version`, `:url` and `:request_headers`, plus whatever
  you pass as `:telemetry_metadata`. On `:stop`, it also holds `:status` and an `:outcome`
  of `:ok`, `:fault` or `:error`.

  Credentials never appear. `:url` has its user info and query removed, and sensitive
  headers such as `Authorization` are masked. Bodies aren't included, except with
  `log_bodies: true`, which adds a `:request_body` with passwords masked.

  ## Logging

  To log each call, attach the default handler once at startup:

      Soap.Telemetry.attach_default_logger(level: :info)
  """

  require Logger

  @sensitive_headers ~w(authorization proxy-authorization cookie set-cookie x-api-key)
  @handler_id "soap-default-logger"

  @doc "Attaches a handler that logs each call. Takes `:level`, which defaults to `:debug`."
  @spec attach_default_logger(keyword()) :: :ok | {:error, :already_exists}
  def attach_default_logger(opts \\ []) do
    level = Keyword.get(opts, :level, :debug)

    :telemetry.attach_many(
      @handler_id,
      [[:soap, :request, :stop], [:soap, :request, :exception]],
      &__MODULE__.handle_event/4,
      %{level: level}
    )
  end

  @doc "Removes the handler added by `attach_default_logger/1`."
  @spec detach_default_logger() :: :ok | {:error, :not_found}
  def detach_default_logger, do: :telemetry.detach(@handler_id)

  @doc false
  def handle_event([:soap, :request, :stop], %{duration: duration}, metadata, %{level: level}) do
    Logger.log(level, fn ->
      "SOAP #{metadata.operation} #{metadata[:outcome]} status=#{metadata[:status]} " <>
        "url=#{metadata.url} in #{System.convert_time_unit(duration, :native, :millisecond)}ms"
    end)
  end

  def handle_event([:soap, :request, :exception], _measurements, metadata, %{level: level}) do
    Logger.log(level, fn -> "SOAP #{metadata.operation} raised: #{inspect(metadata[:reason])}" end)
  end

  @doc false
  def metadata(%Soap.Request{} = request, opts) do
    base = %{
      operation: request.operation,
      version: request.version,
      url: safe_url(request.url),
      request_headers: mask_headers(request.headers)
    }

    base
    |> maybe_add_body(request, opts)
    |> Map.merge(Keyword.get(opts, :telemetry_metadata, %{}))
  end

  defp maybe_add_body(metadata, request, opts) do
    if opts[:log_bodies] do
      Map.put(metadata, :request_body, request.body |> IO.iodata_to_binary() |> mask_body())
    else
      metadata
    end
  end

  @doc false
  def stop_metadata(metadata, {:ok, %Soap.Response{status: status}}) do
    Map.merge(metadata, %{status: status, outcome: :ok})
  end

  def stop_metadata(metadata, {:error, %Soap.Fault{status: status}}) do
    Map.merge(metadata, %{status: status, outcome: :fault})
  end

  def stop_metadata(metadata, {:error, %Soap.Error{reason: reason}}) do
    status =
      case reason do
        {:http_status, code, _} -> code
        _ -> nil
      end

    Map.merge(metadata, %{status: status, outcome: :error, reason: summarize(reason)})
  end

  # Replies can be large and may hold private data, so only their kind is kept.
  defp summarize({:http_status, code, _body}), do: {:http_status, code}
  defp summarize(reason), do: reason

  @doc "Removes credentials from a URL."
  @spec safe_url(String.t()) :: String.t()
  def safe_url(url) do
    url |> URI.parse() |> Map.merge(%{userinfo: nil, query: nil, fragment: nil}) |> URI.to_string()
  end

  @doc "Masks the values of sensitive headers."
  @spec mask_headers(list()) :: list()
  def mask_headers(headers) do
    Enum.map(headers, fn {name, value} ->
      if String.downcase(to_string(name)) in @sensitive_headers, do: {name, "[masked]"}, else: {name, value}
    end)
  end

  @doc "Masks WS-Security secrets in an XML body."
  @spec mask_body(binary()) :: binary()
  def mask_body(xml) do
    Regex.replace(
      ~r/(<(?:[\w.-]+:)?(Password|Nonce|BinarySecurityToken)\b[^>]*>)[^<]*(<\/)/i,
      xml,
      "\\1[masked]\\3"
    )
  end
end
