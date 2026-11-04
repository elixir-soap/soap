defmodule Soap.Conformance.WireServer do
  @moduledoc """
  A scripted HTTP server on a raw socket.

  A framework server would refuse to send most of what these tests need: truncated
  bodies, wrong lengths, and slow or closed connections. A script says exactly which
  bytes go out, so a client can be tested against a broken peer.

  The handler receives `%{method, path, headers, body}` and returns a list of steps:
  a binary to send, `{:sleep, ms}`, or `:close`. The connection always closes after
  the last step.
  """

  defstruct [:listener, :port, :log, :acceptor]

  def start(handler) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, packet: :raw, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(listener)
    {:ok, log} = Agent.start(fn -> [] end)
    acceptor = spawn(fn -> accept_loop(listener, handler, log) end)
    %__MODULE__{listener: listener, port: port, log: log, acceptor: acceptor}
  end

  def stop(%__MODULE__{listener: listener, log: log, acceptor: acceptor}) do
    Process.exit(acceptor, :kill)
    :gen_tcp.close(listener)
    Agent.stop(log)
  end

  def url(%__MODULE__{port: port}, path \\ "/soap"), do: "http://127.0.0.1:#{port}#{path}"

  @doc "A loopback port with nothing listening on it."
  def unused_port do
    {:ok, listener} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(listener)
    :gen_tcp.close(listener)
    port
  end

  @doc "Requests received so far, oldest first."
  def requests(%__MODULE__{log: log}), do: log |> Agent.get(& &1) |> Enum.reverse()

  @doc "Runs `fun` with a server that answers every request with `steps`."
  def with_reply(steps, fun), do: with_handler(fn _request -> steps end, fun)

  @doc "Runs `fun` with a server using `handler`, then stops the server."
  def with_handler(handler, fun) do
    server = start(handler)

    try do
      fun.(server)
    after
      stop(server)
    end
  end

  @doc "A complete HTTP/1.1 response as a single step list."
  def http(status, headers, body) do
    head = Enum.map_join(headers, "", fn {k, v} -> "#{k}: #{v}\r\n" end)
    length = if List.keymember?(headers, "Content-Length", 0), do: "", else: "Content-Length: #{byte_size(body)}\r\n"
    ["HTTP/1.1 #{status} Status\r\n#{head}#{length}Connection: close\r\n\r\n", body]
  end

  defp accept_loop(listener, handler, log) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        pid = spawn(fn -> serve(socket, handler, log) end)
        :gen_tcp.controlling_process(socket, pid)
        send(pid, :go)
        accept_loop(listener, handler, log)

      {:error, _} ->
        :ok
    end
  end

  defp serve(socket, handler, log) do
    receive do
      :go -> :ok
    end

    with {:ok, request} <- read_request(socket) do
      Agent.update(log, &[request | &1])
      Enum.each(List.wrap(handler.(request)), &run_step(&1, socket))
    end

    :gen_tcp.close(socket)
  end

  defp run_step(:close, socket), do: :gen_tcp.close(socket)
  defp run_step({:sleep, ms}, _socket), do: Process.sleep(ms)
  defp run_step(bytes, socket), do: :gen_tcp.send(socket, bytes)

  defp read_request(socket, buffer \\ "") do
    case :binary.split(buffer, "\r\n\r\n") do
      [head, rest] ->
        read_body(socket, parse_head(head), rest)

      [_] ->
        case :gen_tcp.recv(socket, 0, 5_000) do
          {:ok, data} -> read_request(socket, buffer <> data)
          error -> error
        end
    end
  end

  defp parse_head(head) do
    [request_line | lines] = String.split(head, "\r\n")
    [method, path | _] = String.split(request_line, " ")

    headers =
      Enum.map(lines, fn line ->
        [k, v] = String.split(line, ":", parts: 2)
        {String.downcase(k), String.trim(v)}
      end)

    %{method: method, path: path, headers: headers, body: ""}
  end

  defp read_body(socket, request, rest) do
    length =
      case List.keyfind(request.headers, "content-length", 0) do
        {_, value} -> String.to_integer(value)
        nil -> 0
      end

    if byte_size(rest) >= length do
      {:ok, %{request | body: binary_part(rest, 0, length)}}
    else
      case :gen_tcp.recv(socket, 0, 5_000) do
        {:ok, data} -> read_body(socket, request, rest <> data)
        error -> error
      end
    end
  end
end
