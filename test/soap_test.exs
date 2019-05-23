defmodule SoapTest do
  use ExUnit.Case
  import Mock
  alias Soap.{Response, Wsdl}

  @operation "SendMessage"
  @request_params %{inCommonParms: [{"userID", "WSPB"}]}

  test "#call was success" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    response_xml = Fixtures.load_xml("send_service/SendMessageResponse.xml")
    http_poison_result = {:ok, %HTTPoison.Response{status_code: 200, body: response_xml, headers: [], request_url: nil}}

    with_mock HTTPoison, post: fn _, _, _, _ -> http_poison_result end do
      soap_response = %Response{status_code: 200, body: response_xml, headers: [], request_url: nil}
      assert(Soap.call(wsdl, @operation, @request_params) == {:ok, soap_response})
    end
  end

  test "#call can take request options" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    response_xml = Fixtures.load_xml("send_service/SendMessageResponse.xml")
    http_poison_result = {:ok, %HTTPoison.Response{status_code: 200, body: response_xml, headers: [], request_url: nil}}
    hackney = [basic_auth: {"user", "pass"}]

    with_mock HTTPoison, post: fn _, _, _, [hackney: ^hackney] -> http_poison_result end do
      soap_response = %Response{status_code: 200, body: response_xml, headers: [], request_url: nil}
      assert(Soap.call(wsdl, @operation, @request_params, [], hackney: hackney) == {:ok, soap_response})
    end
  end

  test "#call was success, but fault" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    fault_xml = Fixtures.load_xml("send_service/SendMessageFault.xml")
    http_poison_result = {:ok, %HTTPoison.Response{status_code: 500, body: fault_xml, request_url: nil, headers: []}}

    with_mock HTTPoison, post: fn _, _, _, _ -> http_poison_result end do
      soap_response = %Response{status_code: 500, body: fault_xml, headers: [], request_url: nil}
      assert(Soap.call(wsdl, @operation, @request_params) == {:ok, soap_response})
    end
  end

  test "#call returns error" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    http_poison_result = {:error, %HTTPoison.Error{reason: :something_wrong}}

    with_mock HTTPoison, post: fn _, _, _, _ -> http_poison_result end do
      assert(Soap.call(wsdl, @operation, @request_params) == {:error, :something_wrong})
    end
  end

  test "to #call pass unknown soap operation" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    operation = "IncorrectOperation"

    assert_raise OperationError, fn -> Soap.call(wsdl, operation, @request_params) end
  end

  test "#init_model with :url type can take request options" do
    wsdl_path = Fixtures.get_file_path("wsdl/SoapHeader.wsdl")
    {:ok, wsdl_body} = File.read(wsdl_path)
    {_, parsed_wsdl} = Wsdl.parse_from_file(wsdl_path)
    http_poison_result = %HTTPoison.Response{status_code: 200, body: wsdl_body, headers: [], request_url: nil}
    opts = [recv_timeout: 1000]
    opts_with_defaults = [follow_redirect: true, max_redirect: 5, recv_timeout: 1000]

    with_mock HTTPoison, get!: fn _, _, ^opts_with_defaults -> http_poison_result end do
      assert(Soap.init_model(wsdl_path, :url, opts) == {:ok, parsed_wsdl})
    end
  end
end
