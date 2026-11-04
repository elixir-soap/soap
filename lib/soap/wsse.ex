defmodule Soap.WSSE do
  @moduledoc """
  WS-Security `UsernameToken` credentials.

      token = Soap.WSSE.username_token("ann", "secret")
      Soap.call(client, "GetOrders", %{}, wsse: token)

  By default the password goes as plain text, so only use that over HTTPS. Pass
  `digest: true` to send a `PasswordDigest` instead, if the service supports it.

  Each call gets a fresh nonce and timestamp. Message signing and encryption aren't
  supported.
  """

  alias Soap.{Encoder, Raw}

  @wsse "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"
  @wsu "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd"
  @profile "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0"
  @encoding "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary"

  defstruct [:username, :password, digest: false, must_understand: true, timestamp: nil]

  @type t :: %__MODULE__{}

  @doc """
  Makes credentials.

  ## Options

    * `:digest` - send a `PasswordDigest`. Defaults to false.
    * `:must_understand` - set `mustUnderstand` on the header. Defaults to true.
    * `:timestamp` - also send a `wsu:Timestamp` valid for this many seconds.
  """
  @spec username_token(String.t(), String.t(), keyword()) :: t()
  def username_token(username, password, opts \\ []) do
    struct!(%__MODULE__{username: username, password: password}, opts)
  end

  @doc "Builds the SOAP header for these credentials, with a fresh nonce."
  @spec header(t()) :: Raw.t()
  def header(%__MODULE__{} = token), do: header(token, :crypto.strong_rand_bytes(16), DateTime.utc_now())

  @doc false
  def header(%__MODULE__{} = token, nonce, now) do
    created = iso8601(now)

    xml = [
      ~s(<wsse:Security xmlns:wsse="#{@wsse}" xmlns:wsu="#{@wsu}"),
      must_understand(token),
      ">",
      timestamp(token, now),
      "<wsse:UsernameToken>",
      "<wsse:Username>",
      Encoder.escape_text(token.username),
      "</wsse:Username>",
      password(token, nonce, created),
      ~s(<wsse:Nonce EncodingType="#{@encoding}">),
      Base.encode64(nonce),
      "</wsse:Nonce>",
      "<wsu:Created>",
      created,
      "</wsu:Created>",
      "</wsse:UsernameToken>",
      "</wsse:Security>"
    ]

    %Raw{xml: xml}
  end

  # The header's envelope prefix is declared on the envelope, and is always `env`.
  defp must_understand(%__MODULE__{must_understand: true}), do: ~s( env:mustUnderstand="1")
  defp must_understand(_token), do: ""

  defp timestamp(%__MODULE__{timestamp: nil}, _now), do: []

  defp timestamp(%__MODULE__{timestamp: seconds}, now) do
    [
      "<wsu:Timestamp><wsu:Created>",
      iso8601(now),
      "</wsu:Created><wsu:Expires>",
      iso8601(DateTime.add(now, seconds, :second)),
      "</wsu:Expires></wsu:Timestamp>"
    ]
  end

  defp password(%__MODULE__{digest: true, password: password}, nonce, created) do
    digest = :crypto.hash(:sha, [nonce, created, password]) |> Base.encode64()
    [~s(<wsse:Password Type="#{@profile}#PasswordDigest">), digest, "</wsse:Password>"]
  end

  defp password(%__MODULE__{password: password}, _nonce, _created) do
    [~s(<wsse:Password Type="#{@profile}#PasswordText">), Encoder.escape_text(password), "</wsse:Password>"]
  end

  defp iso8601(%DateTime{} = time), do: time |> DateTime.truncate(:millisecond) |> DateTime.to_iso8601()

  defimpl Inspect do
    def inspect(%{username: username, digest: digest}, _opts) do
      "#Soap.WSSE<username: #{inspect(username)}, password: [masked], digest: #{digest}>"
    end
  end
end
