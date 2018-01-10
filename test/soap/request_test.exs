defmodule Soap.RequestTest do
  use ExUnit.Case
  import Mock
  doctest Soap.Request
  alias Soap.Request

  test "#call returns response body" do
    wsdl        = %{endpoint: "test_endpoint.com"}
    soap_action = :testAction
    params      = %{inCommonParms: [{"userID", "WSPB"}]}
    http_poison_result = {:ok, %HTTPoison.Response{status_code: 200, body: "Anything"}}
    {_, %{status_code: _, body: body}} = http_poison_result

    with_mock(HTTPoison, [post!: fn(wsdl, soap_action, params) -> http_poison_result end]) do
      assert(Request.call(wsdl, soap_action, params) == body)
    end
  end
end
