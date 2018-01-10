defmodule Fixtures do
  def get_file_path(file_path) do
    Path.expand("../fixtures/#{file_path}", __DIR__)
  end
end
