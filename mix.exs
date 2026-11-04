defmodule Soap.MixProject do
  use Mix.Project

  @source_url "https://github.com/elixir-soap/soap"
  @version "1.1.1"

  def project do
    [
      app: :soap,
      name: "Soap",
      version: @version,
      elixir: "~> 1.9",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

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
      {:saxy, "~> 1.6"},
      {:sweet_xml, "~> 0.6"},
      {:dialyxir, "~> 1.1.0", only: [:dev, :test], runtime: false},

      # Http && XML
      {:httpoison, "~> 1.0 or ~> 2.0"},
      {:xml_builder, "~> 2.1"},
      {:credo, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, ">= 0.0.0", only: [:dev, :docs], runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:mock, "~> 0.3.0", only: :test},
      # mock pins meck ~> 0.9.2, which no longer compiles on OTP 29.
      {:meck, "~> 1.0", only: :test, override: true},
      {:stream_data, "~> 1.1", only: :test}
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
