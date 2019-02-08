defmodule Soap.MixProject do
  use Mix.Project

  def project do
    [
      app: :soap,
      version: "0.2.0",
      elixir: "~> 1.4",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: description(),
      name: "Soap",
      source_url: "https://github.com/potok-digital/soap"
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

      # Code style
      {:credo, "~> 0.5", only: :dev},

      # Docs
      {:ex_doc, "~> 0.16", only: [:dev, :docs], runtime: false},
      {:inch_ex, "~> 0.2", only: [:dev, :docs]},

      # Http && XML
      {:httpoison, "~> 1.3"},
      {:xml_builder, "~> 2.1"},

      # Mocks for tests
      {:mock, "~> 0.3.0", only: :test}
    ]
  end
end
