defmodule Soap.Service do
  @moduledoc """
  A SOAP service, read from a WSDL.

  Unlike `Soap.Wsdl`, this model follows the document's own links, from binding to
  port type to message to part to schema element, instead of guessing from names. It
  needs no application configuration, and bad input returns `{:error, reason}`.

      {:ok, service} = Soap.Service.load("https://example.com/service?wsdl")
      Soap.Service.operations(service)
      #=> ["Add", "Subtract"]

      {:ok, operation} = Soap.Service.operation(service, "Add", version: "1.2")
      operation.soap_action
      #=> "http://example.com/Add"

  ## Options for `load/2` and `from_string/2`

    * `:import_root` - a directory that local imports must stay inside.
    * `:allow_imports_from` - hosts that imports may be fetched from, or `:all`. See
      `Soap.Service.Loader` for the full rules.
    * `:base` - for `from_string/2`, the path or URL that relative imports resolve against.
    * `:http` - a `Soap.HTTP` implementation.
    * `:http_opts` - options passed to it.
  """

  alias Soap.Schema
  alias Soap.Service.{Loader, Reader}

  defmodule Port do
    @moduledoc "A place a binding can be reached."
    defstruct [:service, :name, :binding, :location, :version]
    @type t :: %__MODULE__{}
  end

  defmodule Part do
    @moduledoc "A message part, defined by a schema element or a schema type."
    defstruct [:name, :element, :type]
    @type t :: %__MODULE__{}
  end

  defmodule Message do
    @moduledoc """
    The input, output or fault side of an operation, as it appears on the wire.

    `body` says what the SOAP Body holds:

      * `{:element, qname}` - a single schema element (document style)
      * `{:rpc, qname}` - a wrapper element named after the operation, with one child per part
      * `:parts` - the parts directly, with no wrapper (bare document style)
      * `:empty` - nothing
    """
    defstruct [:name, :use, :namespace, :encoding_style, :body, parts: [], headers: []]
    @type t :: %__MODULE__{}
  end

  defmodule Header do
    @moduledoc "A SOAP header that an operation declares."
    defstruct [:name, :element, :type, :use, :namespace]
    @type t :: %__MODULE__{}
  end

  defmodule Operation do
    @moduledoc "One operation on one binding. A service offers one per SOAP version it supports."
    defstruct [
      :name,
      :input_name,
      :binding,
      :version,
      :style,
      :soap_action,
      :input,
      :output,
      soap_action_required: false,
      faults: []
    ]

    @type t :: %__MODULE__{}
  end

  defstruct [:target_namespace, operations: [], ports: [], schema: %Schema{}, unresolved_imports: []]

  @type t :: %__MODULE__{
          target_namespace: String.t() | nil,
          operations: [Operation.t()],
          ports: [Port.t()],
          schema: Schema.t(),
          unresolved_imports: [{String.t(), atom()}]
        }

  @doc "Loads a service from a file path or an `http` or `https` URL."
  @spec load(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def load(source, opts \\ []) do
    with {:ok, documents} <- Loader.load(source, opts), do: {:ok, Reader.read(documents)}
  end

  @doc "Loads a service from a WSDL string."
  @spec from_string(binary(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_string(wsdl, opts \\ []) do
    with {:ok, documents} <- Loader.load_string(wsdl, opts), do: {:ok, Reader.read(documents)}
  end

  @doc "The operation names the service offers."
  @spec operations(t()) :: [String.t()]
  def operations(%__MODULE__{operations: operations}) do
    operations |> Enum.map(& &1.name) |> Enum.uniq()
  end

  @doc """
  Finds an operation by name.

  A service can offer an operation on several bindings. Without options, this returns
  the one on the first port that offers it.

  ## Options

    * `:version` - the SOAP version, `"1.1"` or `"1.2"`.
    * `:input` - the input's name, to choose between overloaded operations.
  """
  @spec operation(t(), String.t(), keyword()) :: {:ok, Operation.t()} | {:error, term()}
  def operation(%__MODULE__{} = service, name, opts \\ []) do
    matches =
      service.operations
      |> Enum.filter(&(&1.name == name))
      |> filter_by(:version, opts[:version])
      |> filter_by(:input_name, opts[:input])

    case prefer_first_port(matches, service.ports) do
      nil -> {:error, {:unknown_operation, name, operations(service)}}
      operation -> {:ok, operation}
    end
  end

  @doc "The endpoint URLs of every SOAP port."
  @spec endpoints(t()) :: [String.t()]
  def endpoints(%__MODULE__{ports: ports}) do
    ports |> Enum.map(& &1.location) |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()
  end

  @doc "The endpoint URL for an operation, or nil if no port serves its binding."
  @spec endpoint(t(), Operation.t()) :: String.t() | nil
  def endpoint(%__MODULE__{ports: ports}, %Operation{binding: binding}) do
    Enum.find_value(ports, &(&1.binding == binding && &1.location))
  end

  defp filter_by(operations, _field, nil), do: operations
  defp filter_by(operations, field, value), do: Enum.filter(operations, &(Map.fetch!(&1, field) == value))

  defp prefer_first_port([], _ports), do: nil

  defp prefer_first_port([first | _] = operations, ports) do
    Enum.find_value(ports, first, fn port -> Enum.find(operations, &(&1.binding == port.binding)) end)
  end
end
