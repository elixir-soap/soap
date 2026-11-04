defmodule Soap.Conformance.Driver do
  @moduledoc """
  The contract between the conformance suite and a SOAP client implementation.

  The suite only talks to this behaviour, so the same tests can measure v1 today
  and 2.0 later. To add an implementation, write a driver module and select it
  with `SOAP_CONFORMANCE_DRIVER=v2`.

  ## Params

  Request params are always a list of nodes, `{name, attrs, value}`, in document
  order. `value` is a scalar or a list of nodes. Repeated elements are repeated
  nodes.

  ## Results

  Decoding and calling return one of:

    * `{:ok, term}`: a decoded response. An empty response is `{:ok, nil}`.
    * `{:fault, %{code: String.t(), message: String.t()}}`: a SOAP Fault.
    * `{:error, term}`: anything else that went wrong.

  Drivers must not catch crashes. The harness treats a raise, throw or exit as a
  failed check, because a client that crashes on bad input has a bug.
  """

  @type model :: term()
  @type params :: [{String.t(), map(), term()}]
  @type request :: %{body: iodata(), headers: [{String.t(), String.t()}]}
  @type result :: {:ok, term()} | {:fault, %{code: String.t(), message: String.t()}} | {:error, term()}

  @doc "Loads a WSDL from a local file, following its local imports."
  @callback load(path :: String.t(), opts :: keyword()) :: {:ok, model()} | {:error, term()}

  @doc "Loads a WSDL from a string."
  @callback load_string(wsdl :: binary(), opts :: keyword()) :: {:ok, model()} | {:error, term()}

  @doc "Loads a WSDL from a URL, following its imports."
  @callback load_url(url :: String.t(), opts :: keyword()) :: {:ok, model()} | {:error, term()}

  @doc "Unique operation names in the model."
  @callback operations(model()) :: [String.t()]

  @doc "Endpoint URLs the model knows about."
  @callback endpoints(model()) :: [String.t()]

  @doc "Names of the schema types the model has read, lowercased."
  @callback schema_types(model()) :: [String.t()]

  @doc "Builds a request without sending it."
  @callback build_request(model(), operation :: String.t(), params(), opts :: keyword()) ::
              {:ok, request()} | {:error, term()}

  @doc "Sends a request and decodes the reply."
  @callback call(model(), operation :: String.t(), params(), opts :: keyword()) :: result()

  @doc "Decodes a response. `model` is nil when no WSDL is available."
  @callback decode(
              model() | nil,
              operation :: String.t() | nil,
              status :: pos_integer(),
              headers :: list(),
              body :: binary()
            ) ::
              result()

  @doc """
  Runs `fun` with every outgoing request refused and recorded.

  Returns `{result, attempted_urls}`. This keeps offline layers offline and lets
  security checks prove that nothing was fetched.
  """
  @callback without_network((-> term())) :: {term(), [String.t()]}

  @doc "Runs `fun` with real HTTP allowed. Used against the local wire server."
  @callback with_network((-> term())) :: term()

  @doc "Runs `fun` as an application that has set no configuration for the library."
  @callback without_app_config((-> term())) :: term()

  @doc """
  Options that make a limited implementation load as much as it can.

  Request-building checks use these, so a failure to find operations isn't counted
  twice. A complete implementation returns `[]`.
  """
  @callback tolerant_opts(versions :: [String.t()]) :: keyword()

  @doc "The selected driver module."
  def current do
    case System.get_env("SOAP_CONFORMANCE_DRIVER", "v1") do
      "v1" -> Soap.Conformance.Drivers.V1
      other -> Module.concat([Soap.Conformance.Drivers, String.upcase(other)])
    end
  end

  @doc "Short name of the selected driver, used for its known-failures file."
  def name, do: System.get_env("SOAP_CONFORMANCE_DRIVER", "v1")
end
