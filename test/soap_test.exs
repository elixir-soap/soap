defmodule SoapTest do
  use ExUnit.Case
  doctest Soap

  test "greets the world" do
    assert Soap.hello() == :world
  end
end
