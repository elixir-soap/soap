defmodule Soap.Globals do
  defstruct [:headers, :body, :cookies]

  @moduledoc """
  Documentation for Soap.Globals.
  """

  def init_model(soap_action, headers, body, cookies) do
    %Soap.Globals{
      headers: prepare_headers(soap_action, headers),
      body: prepare_body(body),
      cookies: cookies
    }
  end

  defp prepare_headers(soap_action, headers) do
    %{
      "SOAPAction"     => to_string(soap_action),
      "Content-Type"   => "text/xml;charset=UTF-8"
    } |> Map.merge(headers)
  end

  defp prepare_body(body) do
    {}
  end
end
