defmodule Fixtures do
  def get_file_path(file) do
    Path.expand("../fixtures/#{file}", __DIR__)
  end

  def load_xml(file) do
    xml_path = get_file_path("xml/#{file}")
    File.read!(xml_path)
  end
end
