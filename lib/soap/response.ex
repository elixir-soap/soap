defmodule Soap.Response do
  @moduledoc """
  Documentation for Soap.Response.
  """

  alias Soap.Response.Parser

  defstruct body: nil, headers: [], request_url: nil, status_code: nil

  @type t :: %__MODULE__{
          body: any(),
          headers: list(tuple()),
          request_url: String.t(),
          status_code: pos_integer()
        }

  def parse_body(""), do: %{}
  def parse_body(body), do: Parser.parse(body)
end
