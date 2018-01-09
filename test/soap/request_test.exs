defmodule Soap.RequestTest do
  use ExUnit.Case
  import Mock
  doctest Soap.Request
  alias Soap.Request
  alias Soap.Request.{Options}

  defp generate_request_model do
    wsdl    = %{endpoint: "anyendpoint.com"}
    options = generate_options_model(wsdl)

    %Request{
      url: wsdl[:endpoint],
      headers: options[:headers],
      body: options[:body],
      method: :post,
      options: nil
    }
  end

  defp generate_options_model(wsdl) do
    soap_action = "test"
    params = %{
      "commonParms" => [{"test_k", "test_v"}]
    }
    Options.init_model(soap_action, params)
  end

  test "#init_model" do
    wsdl    = %{endpoint: "anyendpoint.com"}
    options = generate_options_model(wsdl)
    request = generate_request_model
    assert(Request.init_model(wsdl, options)) == request
  end

  test "#call" do
    request = generate_request_model
    values = request |> Map.values
    with_mock(HTTPoison, [request!: fn values -> {:ok, :body} end]) do
      assert(Request.call(request))
    end
  end
end
