defmodule Soap do
  @moduledoc """
  The SOAP client for Elixir based on HTTPoison (for send requests) and SweetXml (for xml parsing).
  The `Soap` module can be used to parse WSDL files:
  iex> Soap.init_model("https://git.io/vNCWd", :url)
  {:ok, %{
    complex_types: [...],
    endpoint: "...",
    messages: [...],
    namespaces: %{...},
    operations: [...],
    schema_attributes: %{...},
    soap_version: "x.x",
    validation_types: %{...}
    }
  }

  And send requests:
  iex> Soap.call(wsdl, action, params)
  {:ok, %Soap.Response{}}

  It's very common to use Soap in order to wrap APIs.
  See `call/5` for more details on how to issue requests to soap services
  """

  alias Soap.{Wsdl, Response, Request}

  @doc """
  Initialization of a WSDL model. Response a map of parsed data from file.
  Returns `{:ok, wsdl}`.

  ## Parameters

  - `path`: Path for wsdl file.
  - `type`: Atom that represents the type of path for WSDL file. Can be `:file` or `url`. Default: `:file`.

  ## Examples

      iex> {:ok, wsdl} = Soap.init_model("https://git.io/vNCWd", :url)
      {:ok, %{...}}
  """
  @spec init_model(String.t(), :file | :url) :: {:ok, map()}
  def init_model(path, type \\ :file)
  def init_model(path, :file), do: Wsdl.parse_from_file(path)
  def init_model(path, :url), do: Wsdl.parse_from_url(path)

  @doc """
  Send a request to the SOAP server based on the passed WSDL file, action and parameters.
  Returns `{:ok, %Soap.Response{}}` if the request is successful, {:error, reason} otherwise.

  ## Parameters

  - `wsdl`: Wsdl model from `Soap.init_model/2` function.
  - `action`: Soap action to be called.
  - `params`: Parameters to build the body of a SOAP request.
  - `headers`: Custom request headers.
  - `opts`: HTTPoison options.

  ## Examples

      iex> Soap.call(wsdl, action, params)
      {:ok, %Soap.Response{}}
  """
  @spec call(wsdl :: map(), operation :: String.t(), params :: map(), headers :: any(), opts :: any()) :: any()
  def call(wsdl, operation, params, headers \\ [], opts \\ []) do
    wsdl
    |> validate_operation(operation)
    |> Request.call(operation, params, headers, opts)
    |> handle_response
  end

  @doc """
  Returns a list of available actions of the passed WSDL.

  ## Parameters

  - `wsdl`: Wsdl model from `Soap.init_model/2` function.

  ## Examples

      iex> {:ok, wsdl} = Soap.init_model("https://git.io/vNCWd", :url)
      iex> Soap.operations(wsdl)
      ["SendMessage", "SendMessageMultipleRecipients"]
  """
  @spec operations(map()) :: nonempty_list(String.t())
  def operations(wsdl) do
    wsdl.operations
  end

  defp handle_response(
         {:ok, %HTTPoison.Response{body: body, headers: headers, request_url: request_url, status_code: status_code}}
       ) do
    {:ok, %Response{body: body, headers: headers, request_url: request_url, status_code: status_code}}
  end

  defp handle_response({:error, %HTTPoison.Error{reason: reason}}) do
    {:error, reason}
  end

  defp validate_operation(wsdl, operation) do
    case valid_operation?(wsdl, operation) do
      false -> raise OperationError, operation
      true -> wsdl
    end
  end

  defp valid_operation?(wsdl, operation) do
    Enum.any?(wsdl[:operations], &(&1[:name] == operation))
  end
end
