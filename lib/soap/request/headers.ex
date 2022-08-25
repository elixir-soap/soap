defmodule Soap.Request.Headers do
  @moduledoc """
  Headers generator by soap action and custom headers.

  ## Examples

      iex> {:ok, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Soap.init_model(:file)
      ...> Soap.Request.Headers.build(wsdl, "SendMessage", [])
      [{"SOAPAction", "com.esendex.ems.soapinterface/SendMessage"}, {"Content-Type", "text/xml;charset=utf-8"}]

  """

  @spec build(map(), String.t(), list()) :: list()
  def build(wsdl, operation, custom_headers) do
    wsdl
    |> extract_soap_action_by_operation(operation)
    |> extract_headers(custom_headers, wsdl)
  end

  @spec extract_soap_action_by_operation(map(), String.t()) :: String.t()
  defp extract_soap_action_by_operation(wsdl, operation) do
    Enum.find(wsdl[:operations], fn x -> x[:name] == operation end)[:soap_action]
  end

  @spec extract_headers(String.t(), list(), map()) :: list()
  defp extract_headers(soap_action, [], wsdl), do: base_headers(soap_action, wsdl)
  defp extract_headers(_, custom_headers, _), do: custom_headers

  @spec base_headers(String.t(), map()) :: list()
  defp base_headers(soap_action, wsdl) do
    uri = URI.parse(wsdl[:endpoint])
    [
#      {"Content-Type", "text/xml;charset=utf-8"},
#      {"User-Agent", "strong-soap/3.4.0"},
      {"Accept", "text/html,application/xhtml+xml,application/xml,text/xml;q=0.9,*/*;q=0.8"},
      {"Accept-Encoding", "none"},
      {"Accept-Charset", "utf-8"},
      {"GET", "#{uri.path} HTTP/1.1}"},
      {"Host", uri.host},
      {"SOAPAction", soap_action},
      {"referer", wsdl[:endpoint]},
    ]
  end
end
