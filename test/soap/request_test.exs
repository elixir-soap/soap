defmodule Soap.RequestTest do
  use ExUnit.Case
  import Mock
  doctest Soap.Request
  alias Soap.Request
  alias Soap.Request.Params

  defp build_params do
    wsdl = %{endpoint: "anyendpoint.com"}
    soap_action = "test"
    params = %{
      "commonParms" => [{"test_k", "test_v"}]
    }
    Params.build(wsdl, soap_action, params)
  end

  test "#call" do
    params = build_params
    values = params |> Map.values
    with_mock(HTTPoison, [request!: fn values -> {:ok, :body} end]) do
      assert(Request.call(values))
    end
  end
end
