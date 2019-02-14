defmodule Fixtures do
  def get_file_path(file) do
    Path.expand("../fixtures/#{file}", __DIR__)
  end

  def load_xml(file) do
    "xml/#{file}"
    |> get_file_path()
    |> File.read!()
    |> String.trim()
  end

  def load_wsdl(file) do
    "wsdl/#{file}"
    |> get_file_path()
    |> File.read!()
  end

  def load_xsd(file) do
    "xsd/#{file}"
    |> get_file_path()
    |> File.read!()
  end
end
