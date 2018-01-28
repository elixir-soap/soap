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
  If body is an empty then parse/1 returns a full parsed response structure as map.
  """
  @spec parse_body(String.t()) :: map()
  def parse_body(body), do: Parser.parse(body)
end
