defmodule Soap.Request.OptionsTest do
  use ExUnit.Case
  doctest Soap.Request.Options
  alias Soap.Request.Options

  test "#build" do
    soap_action = "test"
    params = %{
      "commonParms" => [{"test_k", "test_v"}]
    }
    result = %{
      body: "<commonParms>\n\t<test_k>test_v</test_k>\n</commonParms>",
      headers: nil
    }

    assert(Options.build(soap_action, params)) == result
  end
end
