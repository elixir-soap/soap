defmodule SoapTest do
  use ExUnit.Case
  import Mock
  alias Soap.Wsdl

  @operation "SendMessage"
  @request_params %{inCommonParms: [{"userID", "WSPB"}]}

  test "#call was success" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    http_poison_result = {:ok, %HTTPoison.Response{status_code: 200, body: "Anything", headers: [], request_url: nil}}

    with_mock HTTPoison, post: fn _, _, _ -> http_poison_result end do
      assert(Soap.call(wsdl, @operation, @request_params) == {:ok, %Soap.Response{status_code: 200, body: "Anything"}})
    end
  end

  test "#call was success, but not found" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    http_poison_result = {:ok, %HTTPoison.Response{status_code: 404, body: "Not Found"}}

    with_mock HTTPoison, post: fn _, _, _ -> http_poison_result end do
      assert(Soap.call(wsdl, @operation, @request_params) == {:ok, %Soap.Response{body: "Not Found", status_code: 404}})
    end
  end

  test "#call returns error" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    http_poison_result = {:error, %HTTPoison.Error{reason: :something_wrong}}

    with_mock HTTPoison, post: fn _, _, _ -> http_poison_result end do
      assert(Soap.call(wsdl, @operation, @request_params) == {:error, :something_wrong})
    end
  end

  test "to #call pass unknown soap operation" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    operation = "IncorrectOperation"

    assert_raise OperationError, fn -> Soap.call(wsdl, operation, @request_params) end
  end
end
