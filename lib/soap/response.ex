defmodule Soap.Response do
  @moduledoc """
  Struct for response given by soap call.
  """

  defstruct body: nil, headers: [], request_url: nil, status_code: nil

  @type t :: %__MODULE__{
          body: any(),
          headers: list(tuple()),
          request_url: String.t(),
          status_code: pos_integer()
        }

  alias Soap.Response.Parser

  @doc """
  Executing with xml response body as string.

  Function `parse/1` returns a full parsed response structure as map.
  """
  @spec parse(__MODULE__.t() | String.t(), integer()) :: map()
  def parse(%Soap.Response{body: body, status_code: status_code}), do: parse(body, status_code)
  def parse(body, status_code) when status_code >= 400, do: Parser.parse(body, :fault)
  def parse(body, _status_code), do: Parser.parse(body, :successful)
end
