defmodule Mix.Tasks.Soap.Gen do
  @shortdoc "Generates a client module from a WSDL"

  @moduledoc """
  Generates a client module from a WSDL.

      mix soap.gen priv/calculator.wsdl --module MyApp.Calculator

  ## Options

    * `--module` - the module name. Required.
    * `--output` - the file to write. Defaults to the module's path under `lib/`.
    * `--allow-imports-from` - a host that imports may be fetched from. Can be repeated.
    * `--force` - overwrite an existing file.
  """
  use Mix.Task

  @switches [module: :string, output: :string, allow_imports_from: :keep, force: :boolean]

  @impl true
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)
    if invalid != [], do: Mix.raise("Unknown options: #{inspect(invalid)}")

    source = single_source(positional)
    module = module_name(opts)
    output = output_path(opts, module)

    Application.ensure_all_started(:req)

    case Soap.Service.load(source, allow_imports_from: Keyword.get_values(opts, :allow_imports_from)) do
      {:ok, service} ->
        File.mkdir_p!(Path.dirname(output))
        File.write!(output, Soap.Generator.generate(service, module, source))
        Mix.shell().info("Wrote #{output}, with #{length(Soap.Service.operations(service))} operations")
        warn_unresolved(service)

      {:error, reason} ->
        Mix.raise("Couldn't load #{source}: #{inspect(reason)}")
    end
  end

  defp single_source([source]), do: source

  defp single_source(_other),
    do: Mix.raise("Expected one WSDL path or URL. Usage: mix soap.gen WSDL --module MyApp.Client")

  defp module_name(opts) do
    module = opts[:module] || Mix.raise("--module is required")

    if module =~ ~r/^[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*$/,
      do: module,
      else: Mix.raise("Invalid module name: #{module}")
  end

  defp output_path(opts, module) do
    output = opts[:output] || Path.join("lib", Macro.underscore(module) <> ".ex")
    if File.exists?(output) and !opts[:force], do: Mix.raise("#{output} exists. Use --force to overwrite it.")
    output
  end

  defp warn_unresolved(%{unresolved_imports: []}), do: :ok

  defp warn_unresolved(%{unresolved_imports: imports}) do
    Mix.shell().info("Some types may be missing, because these imports were skipped:")
    Enum.each(imports, fn {location, reason} -> Mix.shell().info("  #{location} (#{reason})") end)
  end
end
