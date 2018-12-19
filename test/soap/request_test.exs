defmodule Soap.RequestTest do
  use ExUnit.Case
  import Mock
  doctest Soap.Request
  alias Soap.{Wsdl, Request}

  @request_with_header """
                       <?xml version="1.0" encoding="UTF-8"?>
                       <env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/" xmlns:tns="http://test.com" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                         <env:Header>
                            <Authentication xmlns="http://test.com">
                               <token>barbaz</token>
                            </Authentication>
                         </env:Header>
                         <env:Body>
                           <tns:sayHello xmlns="http://test.com">
                             <body>Hello John</body>
                           </tns:sayHello>
                         </env:Body>
                       </env:Envelope>
                       """
                       |> String.replace(~r/>\n.*?</, "><")
                       |> String.trim()

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

  test "#get_url returns correct soap:address" do
    endpoint = "http://localhost:8080/soap/SendService"
    {_, wsdl} = Fixtures.get_file_path("wsdl/SendService.wsdl") |> Wsdl.parse_from_file()
    result = wsdl[:endpoint]

    assert result == endpoint
  end

  test "#call takes a tuple with soap headers and params" do
    {_, wsdl} = Fixtures.get_file_path("wsdl/SoapHeader.wsdl") |> Wsdl.parse_from_file()
    operation = "sayHello"
    params = {%{token: "barbaz"}, %{body: "Hello John"}}

    with_mock HTTPoison, post: fn _, body, _, _ -> body end do
      assert(Request.call(wsdl, operation, params) == @request_with_header)
    end
  end
end
