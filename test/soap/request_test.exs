defmodule Soap.RequestTest do
  use ExUnit.Case
  import Mock
  doctest Soap.Request
  alias Soap.{Wsdl, Request}

  test "#call returns response body" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    operation = "SendMessage"
    params = %{inCommonParms: [{"userID", "WSPB"}]}
    http_poison_result = {:ok, %HTTPoison.Response{status_code: 200, body: "Anything"}}

    with_mock HTTPoison, post: fn _, _, _, _ -> http_poison_result end do
      assert(Request.call(wsdl, operation, params) == http_poison_result)
    end
  end

  test "#call can take request options" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    operation = "SendMessage"
    params = %{inCommonParms: [{"userID", "WSPB"}]}
    http_poison_result = {:ok, %HTTPoison.Response{status_code: 200, body: "Anything"}}
    hackney = [basic_auth: {"user", "pass"}]

    with_mock HTTPoison, post: fn _, _, _, [hackney: ^hackney] -> http_poison_result end do
      assert(Request.call(wsdl, operation, params, [], hackney: hackney) == http_poison_result)
    end
  end
end
