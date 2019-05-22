defmodule Soap do
  @moduledoc """
  The SOAP client for Elixir based on HTTPoison (for send requests) and SweetXml (for xml parsing).
  Soap contains 5 main modules:

    * `Soap.Wsdl` - Build wsdl components data map. Can parse raw wsdl file from external url or local path.
    Wsdl which is prepared this module are using for send requests.

    * `Soap.Request` - Provides functionality for build and calling requests. Contains Request.Headers and Soap.Params
    submodules for build headers and build body with parameters validation respectively.
    This module is a wrapper over HTTPoison. It send requests and handle them.

    * `Soap.Response` - Handle soap response and handle them. It provides functionality for parsing xml-like body
    and transform it to comfortable structure. Structure for this module returns with necessary data after send
    a request.

    * `Soap.Xsd` - This module have same functionality as Soap.Wsdl module, but only for Xsd-files. It allows to parse
    xsd files from external resources or local path and convert it to map.

    * `Soap.Type` - Provides a functionality for find and parse complex types from raw xsd file. It uses in library
    for validation parameters when we build request body.

  The `Soap` module can be used to parse WSDL files:
  ```
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
  ```
  And send requests:
  ```elixir
  iex> Soap.call(wsdl, action, params)
  {:ok, %Soap.Response{}}
  ```

  It's very common to use Soap in order to wrap APIs.
  See `call/5` for more details on how to issue requests to soap services
  """

  alias Soap.{Request, Response, Wsdl}

  @doc """
  Initialization of a WSDL model. Response a map of parsed data from file.
  Returns `{:ok, wsdl}`.

  ## Parameters

  - `path`: Path for wsdl file.
  - `type`: Atom that represents the type of path for WSDL file. Can be `:file` or `url`. Default: `:file`.
  - `opts`: HTTPoison options or `:soap_version`.

  ## Examples

      iex> {:ok, wsdl} = Soap.init_model("https://git.io/vNCWd", :url)
      {:ok, %{...}}
  """
  @spec init_model(String.t(), :file | :url, list()) :: {:ok, map()}
  def init_model(path, type \\ :file, opts \\ [])
  def init_model(path, :file, opts), do: Wsdl.parse_from_file(path, opts)
  def init_model(path, :url, opts), do: Wsdl.parse_from_url(path, opts)

  @doc """
  Send a request to the SOAP server based on the passed WSDL file, action and parameters.

  Returns `{:ok, %Soap.Response{}}` if the request is successful, `{:error, reason}` otherwise.

  ## Parameters

  - `wsdl`: Wsdl model from `Soap.init_model/2` function.
  - `action`: Soap action to be called. Use `Soap.operations/1` to get a list of available actions
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
