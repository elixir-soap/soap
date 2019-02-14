defmodule Soap.Request.Params do
  @moduledoc """
  Documentation for Soap.Request.Options.
  """
  import XmlBuilder, only: [element: 3, document: 1, generate: 2]

  @schema_types %{
    "xmlns:xsd" => "http://www.w3.org/2001/XMLSchema",
    "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance"
  }
  @soap_version_namespaces %{
    "1.1" => "http://schemas.xmlsoap.org/soap/envelope/",
    "1.2" => "http://www.w3.org/2003/05/soap-envelope"
  }
  @date_type_regex "[0-9]{4}-[0-9]{2}-[0-9]{2}"
  @date_time_type_regex "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"

  @doc """
  Parsing parameters map and generate body xml by given soap action name and body params(Map).
  Returns xml-like string.
  """

  @spec build_body(wsdl :: map(), operation :: String.t() | atom(), params :: map(), headers :: map()) :: String.t()
  def build_body(wsdl, operation, params, headers) do
    with {:ok, body} <- build_soap_body(wsdl, operation, params),
         {:ok, header} <- build_soap_header(wsdl, operation, headers) do
      [header, body]
      |> add_envelope_tag_wrapper(wsdl, operation)
      |> document
      |> generate(format: :none)
      |> String.replace(["\n", "\t"], "")
    else
      {:error, message} -> message
    end
  end

  @spec validate_params(params :: any(), wsdl :: map(), operation :: String.t()) :: any()
  def validate_params(params, _wsdl, _operation) when is_binary(params), do: params

  def validate_params(params, wsdl, operation) do
    errors =
      params
      |> Enum.map(&validate_param(&1, wsdl, operation))

    case Enum.any?(errors) do
      true ->
        {:error, Enum.reject(errors, &is_nil/1)}

      _ ->
        params
    end
  end

  @spec validate_param(param :: tuple(), wsdl :: map(), operation :: String.t()) :: String.t() | nil
  defp validate_param(param, wsdl, operation) do
    {k, _, v} = param

    case val_map = wsdl.validation_types[String.downcase(operation)] do
      nil ->
        nil

      _ ->
        if Map.has_key?(val_map, k) do
          validate_param_attributes(val_map, k, v)
        else
          "Invalid SOAP message:Invalid content was found starting with element '#{k}'. One of {#{
            Enum.join(Map.keys(val_map), ", ")
          }} is expected."
        end
    end
  end

  @spec validate_param_attributes(val_map :: map(), k :: String.t(), v :: String.t()) :: String.t() | nil
  defp validate_param_attributes(val_map, k, v) do
    attributes = val_map[k]
    [_, type] = String.split(attributes.type, ":")

    case Integer.parse(v) do
      {number, ""} -> validate_type(k, number, type)
      _ -> validate_type(k, v, type)
    end
  end

  defp validate_type(_k, v, "string") when is_binary(v), do: nil
  defp validate_type(k, _v, type = "string"), do: type_error_message(k, type)

  defp validate_type(_k, v, "decimal") when is_number(v), do: nil
  defp validate_type(k, _v, type = "decimal"), do: type_error_message(k, type)

  defp validate_type(k, v, "date") when is_binary(v) do
    case Regex.match?(~r/#{@date_type_regex}/, v) do
      true -> nil
      _ -> format_error_message(k, @date_type_regex)
    end
  end

  defp validate_type(k, _v, type = "date"), do: type_error_message(k, type)

  defp validate_type(k, v, "dateTime") when is_binary(v) do
    case Regex.match?(~r/#{@date_time_type_regex}/, v) do
      true -> nil
      _ -> format_error_message(k, @date_time_type_regex)
    end

    nil
  end

  defp validate_type(k, _v, type = "dateTime"), do: type_error_message(k, type)

  defp build_soap_body(wsdl, operation, params) do
    case params |> construct_xml_request_body |> validate_params(wsdl, operation) do
      {:error, messages} ->
        {:error, messages}

      validated_params ->
        body =
          validated_params
          |> add_action_tag_wrapper(wsdl, operation)
          |> add_body_tag_wrapper

        {:ok, body}
    end
  end

  defp build_soap_header(wsdl, operation, headers) do
    case headers |> construct_xml_request_header do
      {:error, messages} ->
        {:error, messages}

      validated_params ->
        body =
          validated_params
          |> add_header_part_tag_wrapper(wsdl, operation)
          |> add_header_tag_wrapper

        {:ok, body}
    end
  end

  defp type_error_message(k, type) do
    "Element #{k} has wrong type. Expects #{type} type."
  end

  defp format_error_message(k, regex) do
    "Element #{k} has wrong format. Expects #{regex} format."
  end

  @spec construct_xml_request_body(params :: map() | list()) :: list()
  defp construct_xml_request_body(params) when is_map(params) or is_list(params) do
    params |> Enum.map(&construct_xml_request_body/1)
  end

  @spec construct_xml_request_body(params :: tuple()) :: tuple()
  defp construct_xml_request_body(params) when is_tuple(params) do
    params
    |> Tuple.to_list()
    |> Enum.map(&construct_xml_request_body/1)
    |> insert_tag_parameters
    |> List.to_tuple()
  end

  @spec construct_xml_request_body(params :: String.t() | atom() | number()) :: String.t()
  defp construct_xml_request_body(params) when is_atom(params) or is_number(params), do: params |> to_string
  defp construct_xml_request_body(params) when is_binary(params), do: params

  @spec construct_xml_request_header(params :: map() | list()) :: list()
  defp construct_xml_request_header(params) when is_map(params) or is_list(params) do
    params |> Enum.map(&construct_xml_request_header/1)
  end

  @spec construct_xml_request_header(params :: tuple()) :: tuple()
  defp construct_xml_request_header(params) when is_tuple(params) do
    params
    |> Tuple.to_list()
    |> Enum.map(&construct_xml_request_header/1)
    |> insert_tag_parameters
    |> List.to_tuple()
  end

  @spec construct_xml_request_header(params :: String.t() | atom() | number()) :: String.t()
  defp construct_xml_request_header(params) when is_atom(params) or is_number(params), do: params |> to_string
  defp construct_xml_request_header(params) when is_binary(params), do: params

  @spec insert_tag_parameters(params :: list()) :: list()
  defp insert_tag_parameters(params) when is_list(params), do: params |> List.insert_at(1, nil)

  @spec add_action_tag_wrapper(list(), map(), String.t()) :: list()
  defp add_action_tag_wrapper(body, wsdl, operation) do
    action_tag_attributes = handle_element_form_default(wsdl[:schema_attributes])

    action_tag =
      wsdl
      |> get_action_with_namespace(operation)
      |> prepare_action_tag(operation)

    [element(action_tag, action_tag_attributes, body)]
  end

  @spec add_header_part_tag_wrapper(list(), map(), String.t()) :: list()
  defp add_header_part_tag_wrapper(body, wsdl, operation) do
    action_tag_attributes = handle_element_form_default(wsdl[:schema_attributes])

    case get_header_with_namespace(wsdl, operation) do
      nil ->
        nil

      action_tag ->
        [element(action_tag, action_tag_attributes, body)]
    end
  end

  defp handle_element_form_default(%{target_namespace: ns, element_form_default: "qualified"}), do: %{xmlns: ns}
  defp handle_element_form_default(_schema_attributes), do: %{}

  defp prepare_action_tag("", operation), do: operation
  defp prepare_action_tag(action_tag, _operation), do: action_tag

  @spec get_action_with_namespace(wsdl :: map(), operation :: String.t()) :: String.t()
  defp get_action_with_namespace(wsdl, operation) do
    wsdl[:complex_types]
    |> Enum.find(fn x -> x[:name] == operation end)
    |> handle_action_extractor_result(wsdl, operation)
  end

  @spec get_header_with_namespace(wsdl :: map(), operation :: String.t()) :: String.t()
  defp get_header_with_namespace(wsdl, operation) do
    with %{input: %{header: %{message: message, part: part}}} <-
           Enum.find(wsdl[:operations], &(&1[:name] == operation)),
         %{name: name} <- get_message_part(wsdl, message, part) do
      name
    else
      _ -> nil
    end
  end

  defp get_message_part(wsdl, message, part) do
    wsdl[:messages]
    |> Enum.find(&("tns:#{&1[:name]}" == message))
    |> Map.get(:parts)
    |> Enum.find(&(&1[:name] == part))
  end

  defp handle_action_extractor_result(nil, wsdl, operation) do
    wsdl[:complex_types]
    |> Enum.find(fn x -> Macro.camelize(x[:name]) == operation end)
    |> Map.get(:type)
  end

  defp handle_action_extractor_result(result, _wsdl, _operation), do: Map.get(result, :type)

  @spec get_action_namespace(wsdl :: map(), operation :: String.t()) :: String.t()
  defp get_action_namespace(wsdl, operation) do
    wsdl
    |> get_action_with_namespace(operation)
    |> String.split(":")
    |> List.first()
  end

  @spec add_body_tag_wrapper(list()) :: list()
  defp add_body_tag_wrapper(body), do: [element(:"#{env_namespace()}:Body", nil, body)]

  @spec add_header_tag_wrapper(list()) :: list()
  defp add_header_tag_wrapper(body), do: [element(:"#{env_namespace()}:Header", nil, body)]

  @spec add_envelope_tag_wrapper(body :: any(), wsdl :: map(), operation :: String.t()) :: any()
  defp add_envelope_tag_wrapper(body, wsdl, operation) do
    envelop_attributes =
      @schema_types
      |> Map.merge(build_soap_version_attribute(wsdl))
      |> Map.merge(build_action_attribute(wsdl, operation))
      |> Map.merge(custom_namespaces())

    [element(:"#{env_namespace()}:Envelope", envelop_attributes, body)]
  end

  @spec build_soap_version_attribute(Map.t()) :: map()
  defp build_soap_version_attribute(wsdl) do
    soap_version = wsdl |> soap_version() |> to_string
    %{"xmlns:#{env_namespace()}" => @soap_version_namespaces[soap_version]}
  end

  @spec build_action_attribute(map(), String.t()) :: map()
  defp build_action_attribute(wsdl, operation) do
    action_attribute_namespace = get_action_namespace(wsdl, operation)
    action_attribute_value = wsdl[:namespaces][action_attribute_namespace][:value]
    prepare_action_attribute(action_attribute_namespace, action_attribute_value)
  end

  defp prepare_action_attribute(_action_attribute_namespace, nil), do: %{}

  defp prepare_action_attribute(action_attribute_namespace, action_attribute_value) do
    %{"xmlns:#{action_attribute_namespace}" => action_attribute_value}
  end

  defp soap_version(wsdl) do
    Map.get(wsdl, :soap_version, Application.fetch_env!(:soap, :globals)[:version])
  end

  defp env_namespace, do: Application.fetch_env!(:soap, :globals)[:env_namespace] || :env
  defp custom_namespaces, do: Application.fetch_env!(:soap, :globals)[:custom_namespaces] || %{}
end
