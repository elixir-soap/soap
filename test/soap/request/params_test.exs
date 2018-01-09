defmodule Soap.Request.ParamsTest do
  use ExUnit.Case
  doctest Soap.Request.Params
  alias Soap.Request.Params

  test "#build" do
    wsdl = %{endpoint: "anyendpoint.com"}
    soap_action = "test"
    params = %{
      "commonParms" => [{"test_k", "test_v"}]
    }
    result = %{
      body: "<commonParms>\n\t<test_k>test_v</test_k>\n</commonParms>",
      headers: nil,
      method: :post,
      options: nil,
      url: "anyendpoint.com"
    }

    assert(Params.build(wsdl, soap_action, params)) == result
  end
end
