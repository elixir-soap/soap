defmodule Fixtures do
  @moduledoc false

  def get_file_path(file) do
    Path.expand("../fixtures/#{file}", __DIR__)
  end

  def load_xml(file) do
    get_file_path("xml/#{file}")
    |> File.read!()
    |> String.trim()
  end

  def load_wsdl(file) do
    get_file_path("wsdl/#{file}")
    |> File.read!()
  end
end
