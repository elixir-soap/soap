# Soap
[![Build Status](https://travis-ci.org/potok-digital/soap.svg?branch=master)](https://travis-ci.org/potok-digital/soap)
[![Code coverage](https://img.shields.io/coveralls/github/potok-digital/soap.svg?style=flat)](https://coveralls.io/github/potok-digital/soap)

Pure Elixir implementation of SOAP client

## NOTE: Library is NOT production ready before 1.0 version

## Installation

1) Add `soap` to your deps:

```elixir
def deps do
  [{:soap, "~> 0.2.1"}]
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
wsdl_path = "http://www.dneonline.com/calculator.asmx?WSDL"
action = "Add"
params = %{intA: 1, intB: 2}

# Parse wsdl file for execution of action on its basis
{:ok, wsdl} = Soap.init_model(wsdl_path, :url)

# Call action
{:ok, %Soap.Response{body: body, headers: headers, request_url: url, status_code: code}} = Soap.call(wsdl, action, params)

# Parse body
Soap.Response.parse(body, code)
```

To add SOAP headers, pass in a `{headers, params}` tuple instead of just params.

```elixir
%Soap.Response{} = Soap.call(wsdl, action, {%{Token: "foo"}, params})
```
