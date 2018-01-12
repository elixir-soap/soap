defmodule Fixtures do
  def get_file_path(file) do
    Path.expand("../fixtures/#{file}", __DIR__)
  end

  def load_xml(file) do
    xml_path = get_file_path("xml/#{file}")
    xml_path
    |> File.read!
    |> String.trim
  end

  def load_wsdl(file) do
    wsdl_path = get_file_path("wsdl/#{file}")
    File.read!(wsdl_path)
  end
end
