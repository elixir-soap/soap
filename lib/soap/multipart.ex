defmodule Soap.Multipart do
  @moduledoc """
  Reads and writes `multipart/related` messages, as used by MTOM and SOAP with Attachments.
  """

  alias Soap.Attachment

  @doc """
  Splits a multipart body into the root part and its attachments.

  Returns `:not_multipart` for any other content type.
  """
  @spec parse(String.t() | nil, binary()) ::
          :not_multipart | {:ok, binary(), [Attachment.t()]} | {:error, term()}
  def parse(content_type, body) do
    if String.starts_with?(String.downcase(content_type || ""), "multipart/") do
      parse_multipart(content_type, body)
    else
      parse_by_first_line(body)
    end
  end

  # Some gateways lose or rewrite the content type. A body that opens with a boundary
  # can't be anything else.
  defp parse_by_first_line(body) do
    trimmed = String.trim_leading(body)

    with "--" <> rest <- trimmed,
         [boundary, _] <- String.split(rest, ~r/\r?\n/, parts: 2),
         true <- boundary != "" and not String.contains?(boundary, " ") do
      case split(trimmed, boundary) do
        [] -> :not_multipart
        parts -> choose_root(parts, nil)
      end
    else
      _ -> :not_multipart
    end
  end

  defp parse_multipart(content_type, body) do
    case parameter(content_type, "boundary") do
      nil ->
        {:error, :no_multipart_boundary}

      boundary ->
        case split(body, boundary) do
          [] -> {:error, :empty_multipart}
          parts -> choose_root(parts, parameter(content_type, "start"))
        end
    end
  end

  defp choose_root(parts, start) do
    id = start && strip_brackets(start)
    root = (id && Enum.find(parts, &(&1.id == id))) || hd(parts)
    {:ok, root.data, parts |> List.delete(root)}
  end

  defp split(body, boundary) do
    delimiter = "--" <> boundary

    body
    |> :binary.split(delimiter, [:global])
    |> Enum.drop(1)
    |> Enum.take_while(&(not String.starts_with?(&1, "--")))
    |> Enum.map(&parse_part/1)
  end

  defp parse_part(raw) do
    raw = raw |> String.replace_prefix("\r\n", "") |> String.replace_prefix("\n", "")
    {head, content} = split_head(raw)
    headers = parse_headers(head)
    content = content |> String.replace_suffix("\r\n", "") |> String.replace_suffix("\n", "")

    %Attachment{
      id: headers |> List.keyfind("content-id", 0, {nil, nil}) |> elem(1) |> strip_brackets(),
      content_type: headers |> List.keyfind("content-type", 0, {nil, "application/octet-stream"}) |> elem(1),
      headers: headers,
      data: decode_transfer(content, List.keyfind(headers, "content-transfer-encoding", 0))
    }
  end

  defp split_head(raw) do
    case :binary.split(raw, "\r\n\r\n") do
      [head, content] -> {head, content}
      [_] -> split_head_lf(raw)
    end
  end

  defp split_head_lf(raw) do
    case :binary.split(raw, "\n\n") do
      [head, content] -> {head, content}
      [only] -> {"", only}
    end
  end

  defp parse_headers(head) do
    head
    |> String.split(~r/\r?\n/, trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, ":", parts: 2) do
        [name, value] -> [{String.downcase(String.trim(name)), String.trim(value)}]
        _ -> []
      end
    end)
  end

  defp decode_transfer(content, {_, encoding}) do
    case String.downcase(encoding) do
      "base64" -> decode_base64(content)
      _ -> content
    end
  end

  defp decode_transfer(content, nil), do: content

  defp decode_base64(content) do
    case content |> String.replace(~r/\s/, "") |> Base.decode64() do
      {:ok, bytes} -> bytes
      :error -> content
    end
  end

  defp strip_brackets(nil), do: nil
  defp strip_brackets(value), do: value |> String.trim() |> String.trim_leading("<") |> String.trim_trailing(">")

  # Reads a parameter from a header value, keeping its case. Boundaries are case-sensitive.
  defp parameter(header, name) do
    case Regex.run(~r/;\s*#{name}\s*=\s*(?:"([^"]*)"|([^;\s]+))/i, header) do
      [_, quoted] -> quoted
      [_, "", plain] -> plain
      nil -> nil
    end
  end

  @doc """
  Builds an MTOM message from the SOAP XML and its attachments.

  Returns the content type and body. `action_type` is the root part's own type,
  `text/xml` for SOAP 1.1 and `application/soap+xml` for SOAP 1.2.
  """
  @spec build(binary(), [Attachment.t()], String.t()) :: {String.t(), iodata()}
  def build(xml, attachments, action_type) do
    boundary = "soap-" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
    root_id = "root@soap"

    root = [
      "--",
      boundary,
      "\r\nContent-Type: application/xop+xml; charset=UTF-8; type=\"",
      action_type,
      "\"\r\nContent-Transfer-Encoding: 8bit\r\nContent-ID: <",
      root_id,
      ">\r\n\r\n",
      xml,
      "\r\n"
    ]

    parts =
      Enum.map(attachments, fn attachment ->
        [
          "--",
          boundary,
          "\r\nContent-Type: ",
          attachment.content_type,
          "\r\nContent-Transfer-Encoding: binary\r\nContent-ID: <",
          attachment.id,
          ">\r\n\r\n",
          attachment.data,
          "\r\n"
        ]
      end)

    content_type =
      ~s(multipart/related; type="application/xop+xml"; boundary="#{boundary}"; start="<#{root_id}>"; start-info="#{action_type}")

    {content_type, [root, parts, "--", boundary, "--\r\n"]}
  end
end
