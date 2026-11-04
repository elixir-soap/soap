defmodule Soap.Request do
  @moduledoc "A request ready to send: where it goes, its headers and its body."

  alias Soap.Service.Operation

  defstruct [:url, :operation, :version, :body, headers: [], attachments: []]

  @type t :: %__MODULE__{
          url: String.t() | nil,
          operation: String.t(),
          version: String.t(),
          body: iodata(),
          headers: [{String.t(), String.t()}],
          attachments: [Soap.Attachment.t()]
        }

  @doc """
  The HTTP headers an operation needs, plus any custom ones.

  SOAP 1.1 uses a quoted `SOAPAction` header and `text/xml`. SOAP 1.2 puts the action in
  `application/soap+xml`. A custom header replaces one of the same name.
  """
  @spec headers(Operation.t(), [{String.t(), String.t()}]) :: [{String.t(), String.t()}]
  def headers(%Operation{version: "1.1", soap_action: action}, custom) do
    merge([{"SOAPAction", ~s("#{action}")}, {"Content-Type", "text/xml; charset=utf-8"}], custom)
  end

  def headers(%Operation{version: "1.2", soap_action: action}, custom) do
    merge([{"Content-Type", content_type_12(action)}], custom)
  end

  defp content_type_12(action) when action in [nil, ""], do: "application/soap+xml; charset=utf-8"
  defp content_type_12(action), do: ~s(application/soap+xml; charset=utf-8; action="#{action}")

  defp merge(base, custom) do
    names = Enum.map(custom, fn {name, _} -> String.downcase(to_string(name)) end)
    Enum.reject(base, fn {name, _} -> String.downcase(name) in names end) ++ custom
  end
end
