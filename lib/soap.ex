defmodule Soap do
  @moduledoc """
  Documentation for Soap.
  """

  alias Soap.Wsdl
  alias Soap.Request

  @spec init_model(String.t(), :file | :url) :: {:ok, map()}
  def init_model(path, type \\ :file)
  def init_model(path, :file), do: Wsdl.parse_from_file(path)
  def init_model(path, :url), do: Wsdl.parse_from_url(path)

  @spec call(map(), String.t(), map(), any()) :: any()
  def call(wsdl, soap_action, params, headers \\ []) do
    Request.call(wsdl, soap_action, params, headers)
  end

  @spec operations(map()) :: nonempty_list(String.t())
  def operations(wsdl) do
    wsdl.operations
    |> Enum.map(&(&1.name))
  end
end
