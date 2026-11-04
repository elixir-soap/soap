Code.require_file("support/fixtures.exs", __DIR__)

# :nightly needs the full harvest and :live needs the internet. See test/corpus/README.md.
ExUnit.start(exclude: [:nightly, :live])

Soap.Conformance.Harness.start()
