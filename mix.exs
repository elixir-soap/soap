defmodule Soap.MixProject do
  use Mix.Project

  def project do
    [
      app: :soap,
      version: "0.2.1",
      elixir: "~> 1.4",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: description(),
      name: "Soap",
      source_url: "https://github.com/potok-digital/soap",
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
      files: ["lib", "mix.exs", "README.md", "LICENSE*"],
      maintainers: ["Petr Stepchenko", "Roman Kakorin"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/potok-digital/soap"}
    ]
  end

  defp description do
    """
    Pure Elixir implementation of SOAP client
    """
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:sweet_xml, "~> 0.6.5"},

      # Http && XML
      {:httpoison, "~> 1.3"},
      {:xml_builder, "~> 2.1"},

      # Code style
      {:credo, "~> 1.0", only: [:dev, :test]},

      # Docs
      {:ex_doc, "~>  0.19.3", only: [:dev, :docs], runtime: false},

      # Testing
      {:mock, "~> 0.3.0", only: :test},
      {:excoveralls, "~> 0.10", only: :test}
    ]
  end
end
