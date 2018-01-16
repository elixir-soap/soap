defmodule Soap.RequestTest do
  use ExUnit.Case
  import Mock
  doctest Soap.Request
  alias Soap.{Wsdl, Request}

  test "#call returns response body" do
    {_, wsdl}   = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file
    operation   = "SendMessage"
    params      = %{inCommonParms: [{"userID", "WSPB"}]}
    http_poison_result = {:ok, %HTTPoison.Response{status_code: 200, body: "Anything"}}

    with_mock(HTTPoison, [post!: fn(_, _, _) -> http_poison_result end]) do
      assert(Request.call(wsdl, operation, params) == http_poison_result)
    end
  end
end
