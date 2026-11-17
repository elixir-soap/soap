defmodule Soap.Client do
  @moduledoc "A loaded service with default call options. Make one with `Soap.load/2`."
  defstruct [:service, opts: []]
  @type t :: %__MODULE__{service: Soap.Service.t(), opts: keyword()}
end

defmodule Soap.Response do
  @moduledoc """
  A complete reply.

    * `status` and `headers` - from HTTP.
    * `body` - the raw body.
    * `result` - the decoded SOAP Body. See `Soap.Decoder`.
    * `soap_headers` - the decoded SOAP Header.
    * `attachments` - any parts that weren't resolved into the result.
  """
  defstruct [:status, :body, :result, headers: [], soap_headers: %{}, attachments: []]

  @type t :: %__MODULE__{
          status: pos_integer(),
          headers: list(),
          body: binary(),
          result: term(),
          soap_headers: map(),
          attachments: [Soap.Attachment.t()]
        }

  @doc false
  def new(status, headers, body, %Soap.Decoder.Decoded{} = decoded) do
    %__MODULE__{
      status: status,
      headers: headers,
      body: body,
      result: decoded.result,
      soap_headers: decoded.soap_headers,
      attachments: decoded.attachments
    }
  end
end
