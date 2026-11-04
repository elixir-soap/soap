Code.require_file("support/fixtures.exs", __DIR__)

Soap.Conformance.Harness.start()

# :nightly needs the full harvest and :live needs the internet. See test/corpus/README.md.
ExUnit.start(exclude: [:nightly, :live])
