defmodule Soap.Raw do
  @moduledoc """
  XML to send exactly as given.

  Use it for prebuilt fragments, or to skip escaping for a large value you know is safe.
  Nothing checks this content, so never build it from untrusted input.

      Soap.call(client, "Upload", %{"Document" => %Soap.Raw{xml: fragment}})
  """
  @enforce_keys [:xml]
  defstruct [:xml]
  @type t :: %__MODULE__{xml: iodata()}
end

defmodule Soap.Attachment do
  @moduledoc """
  Binary content sent or received outside the XML.

  As a param value, it's sent by MTOM: the element holds an `xop:Include` pointing to a
  separate part. Passed in the `:attachments` option, it's sent as a SOAP-with-Attachments
  part with no reference in the XML.
  """
  @enforce_keys [:data]
  defstruct [:data, :id, content_type: "application/octet-stream", headers: []]

  @type t :: %__MODULE__{
          data: binary(),
          id: String.t() | nil,
          content_type: String.t(),
          headers: [{String.t(), String.t()}]
        }
end

defmodule Soap.Error do
  @moduledoc """
  Anything that went wrong, other than a SOAP Fault.

  `reason` says what. Common values:

    * `{:invalid_param, path, message}` - a param doesn't fit the schema. Nothing was sent.
    * `{:unknown_operation, name, available}`
    * `{:http_status, status, body}` - an error status with no SOAP Fault in the reply.
    * `{:transport, reason}` - no reply at all, such as a timeout or a refused connection.
    * `{:invalid_xml, message}`, `:no_envelope`, `:doctype_not_allowed` - a broken reply.
    * `:no_endpoint` - the WSDL gives no address for this operation, and none was passed.
  """
  defexception [:reason]

  @type t :: %__MODULE__{reason: term()}

  @impl true
  def message(%__MODULE__{reason: reason}), do: "SOAP error: #{inspect(reason)}"
end

defmodule Soap.Fault do
  @moduledoc """
  A SOAP Fault from the server, in either SOAP version.

    * `code` - the fault code as sent, such as `"soap:Server"`.
    * `subcodes` - SOAP 1.2 subcodes, outermost first.
    * `message` - the human-readable text.
    * `actor` - who raised it: `faultactor` in 1.1, `Role` in 1.2.
    * `detail` - the decoded detail, if any.
    * `status` - the HTTP status it arrived with.
  """
  defexception [:code, :message, :actor, :detail, :status, subcodes: []]

  @type t :: %__MODULE__{
          code: String.t() | nil,
          subcodes: [String.t()],
          message: String.t() | nil,
          actor: String.t() | nil,
          detail: term(),
          status: pos_integer() | nil
        }

  @impl true
  def message(%__MODULE__{code: code, message: message}), do: "SOAP fault #{code}: #{message}"
end
