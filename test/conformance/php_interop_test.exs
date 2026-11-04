defmodule Soap.Conformance.PhpInteropTest do
  @moduledoc """
  Replies from PHP's SOAP interop suite (SOAPBuilders rounds 2 to 4), extracted from
  php-src's `.phpt` files: every data type, in rpc/encoded and document styles.

  These files hold no expected result in a form this suite can read, so each check proves
  that an envelope decodes to clean data. The WSDL-driven and live layers check values.
  """
  use ExUnit.Case

  alias Soap.Conformance.{Driver, Harness, Support}

  @moduletag capture_log: true

  test "an envelope in the wrong namespace is an error" do
    body = "golden/php-interop/r4_groupH_soapfault_003w_0.xml" |> Support.corpus_path() |> File.read!()
    assert {:error, :no_envelope} = Driver.current().decode(nil, nil, 200, [], body)
  end

  # This one tests VersionMismatch, so its envelope is deliberately in the wrong namespace.
  @wrong_version "r4_groupH_soapfault_003w_0"

  for path <- "golden/php-interop/*.xml" |> Support.corpus_path() |> Path.wildcard() |> Enum.sort(),
      Path.basename(path, ".xml") != @wrong_version do
    @path path
    @external_resource path
    @name Path.basename(path, ".xml")

    test "#{@name}" do
      Harness.check("php_interop/#{@name}", fn ->
        result = Driver.current().decode(nil, nil, 200, [], File.read!(@path))

        case result do
          {:ok, decoded} ->
            dirty = decoded |> Support.keys() |> Enum.filter(&(String.contains?(&1, ":") or &1 == "xmlns"))
            assert dirty == []

          {:fault, %{message: message}} ->
            assert is_binary(message)
        end
      end)
    end
  end
end
