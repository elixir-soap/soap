defmodule Soap.MixProject do
  use Mix.Project

  @source_url "https://github.com/elixir-soap/soap"
  @version "2.0.0"

  def project do
    [
      app: :soap,
      name: "Soap",
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp package do
    [
      description: "SOAP client for Elixir: schema-aware requests and results, MTOM, WS-Security",
      files: ["lib", "mix.exs", "README.md", "MIGRATING.md", "LICENSE*", "CHANGELOG*"],
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
      {:req, "~> 0.5"},
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:stream_data, "~> 1.1", only: :test},
      # Only to test that %Decimal{} params work. The library itself doesn't use it.
      {:decimal, "~> 3.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:dev, :docs], runtime: false}
    ]
  end

  defp docs do
    [
      extras: [
        "CHANGELOG.md": [],
        "LICENSE.md": [title: "License"],
        "README.md": [title: "Overview"],
        "MIGRATING.md": [title: "Migrating from 1.x"]
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      formatters: ["html"],
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  # Shows GitHub alerts, such as `> [!CAUTION]`, as ExDoc admonitions.
  defp before_closing_body_tag(:html) do
    """
    <script>
      (() => {
        const kinds = {NOTE: "info", TIP: "tip", IMPORTANT: "info", WARNING: "warning", CAUTION: "error"};

        for (const quote of document.querySelectorAll("blockquote")) {
          const first = quote.querySelector(":scope > p");
          const match = first && first.innerHTML.match(/^\\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\\]\\s*/);
          if (!match) continue;

          const kind = kinds[match[1]];
          const section = document.createElement("section");
          section.setAttribute("role", "note");
          section.className = `admonition ${kind}`;

          const title = document.createElement("h4");
          title.className = `admonition-title ${kind}`;
          title.textContent = match[1][0] + match[1].slice(1).toLowerCase();

          first.innerHTML = first.innerHTML.slice(match[0].length);
          if (first.innerHTML.trim() === "") first.remove();

          section.append(title, ...quote.childNodes);
          quote.replaceWith(section);
        }
      })();
    </script>
    """
  end

  defp before_closing_body_tag(_format), do: ""
end
