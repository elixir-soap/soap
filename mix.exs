defmodule Soap.MixProject do
  use Mix.Project

  @source_url "https://github.com/elixir-soap/soap"
  @version "1.0.1"

  def project do
    [
      app: :soap,
      name: "Soap",
      version: @version,
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp package do
    [
      description: "SOAP client for Elixir programming language",
      files: ["lib", "mix.exs", "README.md", "LICENSE*", "CHANGELOG*"],
      maintainers: ["Petr Stepchenko", "Roman Kakorin"],
      licenses: ["MIT"],
      links: %{
        "Changelog" => "https://hexdocs.pm/soap/changelog.html",
        "GitHub" => @source_url
      }
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:sweet_xml, "~> 0.6"},
      {:httpoison, "~> 1.3"},
      {:xml_builder, "~> 2.1"},
      {:credo, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, ">= 0.0.0", only: [:dev, :docs], runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:mock, "~> 0.3.0", only: :test}
    ]
  end

  defp docs do
    [
      extras: [
        "CHANGELOG.md": [],
        "LICENSE.md": [title: "License"],
        "README.md": [title: "Overview"]
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end
end
