# Soap

[![Build Status](https://travis-ci.org/elixir-soap/soap.svg?branch=master)](https://travis-ci.org/elixir-soap/soap)
[![Code coverage](https://img.shields.io/coveralls/github/elixir-soap/soap.svg?style=flat)](https://coveralls.io/github/elixir-soap/soap)
[![Module Version](https://img.shields.io/hexpm/v/soap.svg)](https://hex.pm/packages/soap)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/soap/)
[![Total Download](https://img.shields.io/hexpm/dt/soap.svg)](https://hex.pm/packages/soap)
[![License](https://img.shields.io/hexpm/l/soap.svg)](https://github.com/elixir-soap/soap/blob/master/LICENSE.md)
[![Last Updated](https://img.shields.io/github/last-commit/elixir-soap/soap.svg)](https://github.com/elixir-soap/soap/commits/master)

SOAP client for Elixir programming language.

## Installation

Add `:soap` to your deps:

```elixir
def deps do
  [
    {:soap, "~> 1.0"}
  ]
end
```
Add `:soap` to the list of application dependencies(or just use `extra_applications`):

```elixir
def application do
  [
    applications: [:logger, :soap]
  ]
end
```

## Configuration

Configure version of SOAP protocol. Supported versions `1.1`(default) and `1.2`:

```elixir
config :soap, :globals, version: "1.1"
```

## Usage

The documentation is available on [HexDocs](https://hexdocs.pm/soap/api-reference.html).

Parse WSDL file for execution of actions on its basis:

```elixir
iex> {:ok, wsdl} = Soap.init_model(wsdl_path, :url)
{:ok, parsed_wsdl}
```

Get list of available operations:

```elixir
iex> Soap.operations(wsdl)
[
  %{
    input: %{body: nil, header: nil},
    name: "Add",
    soap_action: "http://tempuri.org/Add"
  },
  %{
    input: %{body: nil, header: nil},
    name: "Subtract",
    soap_action: "http://tempuri.org/Subtract"
  },
  %{
    input: %{body: nil, header: nil},
    name: "Multiply",
    soap_action: "http://tempuri.org/Multiply"
  },
  %{
    input: %{body: nil, header: nil},
    name: "Divide",
    soap_action: "http://tempuri.org/Divide"
  }
]
```

Call action:

```elixir
wsdl_path = "http://www.dneonline.com/calculator.asmx?WSDL"
action = "Add"
params = %{intA: 1, intB: 2}

iex> {:ok, response} = Soap.call(wsdl, action, params)
{:ok,
 %Soap.Response{
   body: "<?xml version=\"1.0\" encoding=\"utf-8\"?><soap:Envelope xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\"><soap:Body><AddResponse xmlns=\"http://tempuri.org/\"><AddResult>3</AddResult></AddResponse></soap:Body></soap:Envelope>",
   headers: [
     {"Cache-Control", "private, max-age=0"},
     {"Content-Length", "325"},
     {"Content-Type", "text/xml; charset=utf-8"},
     {"Server", "Microsoft-IIS/7.5"},
     {"X-AspNet-Version", "2.0.50727"},
     {"X-Powered-By", "ASP.NET"},
     {"Date", "Thu, 14 Feb 2019 07:52:04 GMT"}
   ],
   request_url: "http://www.dneonline.com/calculator.asmx",
   status_code: 200
 }}
```

Safe strings:

You might have strings that you know are safe where you'd like to skip the escaping step in generating the XML (for example if you have a lot of Base64 encoded data).  For this situation you can mark data as "safe":

```elixir
params = %{data: {:__safe, data}}
```

Parse response:

```elixir
iex> Soap.Response.parse(response)
%{AddResponse: %{AddResult: "3"}}
```

To add SOAP headers, pass in a `{headers, params}` tuple instead of just params:

```elixir
{:ok, %Soap.Response{}} = Soap.call(wsdl, action, {%{Token: "foo"}, params})
```

## Contributing
We appreciate any contribution and open to [future requests](https://github.com/elixir-soap/soap/pulls).

You can find a list of features and bugs in the [issue tracker](https://github.com/elixir-soap/soap/issues).

## Copyright and License

Copyright (c) 2017 Petr Stepchenko

This work is free. You can redistribute it and/or modify it under the
terms of the MIT License. See the [LICENSE.md](./LICENSE.md) file for more details.
