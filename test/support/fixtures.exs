defmodule Fixtures do
  def get_file_path(file) do
    Path.expand("../fixtures/#{file}", __DIR__)
  end
end
