# Soap
[![Build Status](https://travis-ci.org/potok-digital/soap.svg?branch=master)](https://travis-ci.org/potok-digital/soap)

Pure Elixir implementation of SOAP client

## NOTE: Library is NOT production ready before 1.0 version

<!--
## Installation

1) Add `soap` to your deps:

```elixir
def deps do
  [{:soap, "~> 0.1.0"}]
end
```
2) Add `soap` to the list of application dependencies

```elixir
def application do
  [applications: [:logger, :soap]]
end
```

## Usage

```elixir
wsdl_path = "https://git.io/vNCWd"
action = "sendMessage"
params = %{recipient: "1", body: ""}

# Parse wsdl file for execution of action on its basis
{:ok, wsdl} = Soap.init_model(wsdl_path, :url)

# Call action
Soap.call(wsdl, action, params)

# Cache the wsdl to do recurrent calls quickly
{:ok, body} = Detergentex.init_model(wsdl_url)
```
