# Soap
[![Build Status](https://travis-ci.org/elixir-soap/soap.svg?branch=master)](https://travis-ci.org/elixir-soap/soap)
[![Code coverage](https://img.shields.io/coveralls/github/elixir-soap/soap.svg?style=flat)](https://coveralls.io/github/elixir-soap/soap)
[![Hex version](https://img.shields.io/hexpm/v/soap.svg?style=flat)](https://hex.pm/packages/soap)
[![Hex license](https://img.shields.io/hexpm/l/soap.svg?style=flat)](https://hex.pm/packages/soap)
[![Hex downloads](https://img.shields.io/hexpm/dt/soap.svg?style=flat)](https://hex.pm/packages/soap)

SOAP client for Elixir programming language

## Installation

1) Add `soap` to your deps:

```elixir
def deps do
  [{:soap, "~> 1.0"}]
end
```
2) Add `soap` to the list of application dependencies(or just use extra_applications):

```elixir
def application do
  [applications: [:logger, :soap]]
end
```

## Configuration

Configure version of SOAP protocol. Supported versions `1.1`(default) and `1.2`.
```elixir
config :soap, :globals, version: "1.1"
```

## Usage

The documentation is available on [HexDocs](https://hexdocs.pm/soap/api-reference.html).

Parse WSDL file for execution of actions on its basis:
```elixir
iex(1)> {:ok, wsdl} = Soap.init_model(wsdl_path, :url)
{:ok, parsed_wsdl}
```

Get list of available operations:
```elixir
iex(2)> Soap.operations(wsdl)
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

iex(3)> {:ok, response} = Soap.call(wsdl, action, params)
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

Parse response:
```elixir
iex(4)> Soap.Response.parse(response)
%{AddResponse: %{AddResult: "3"}}
```

To add SOAP headers, pass in a `{headers, params}` tuple instead of just params:
```elixir
{:ok, %Soap.Response{}} = Soap.call(wsdl, action, {%{Token: "foo"}, params})
```

## Contributing
We appreciate any contribution and open to [future requests](https://github.com/elixir-soap/soap/pulls).

You can find a list of features and bugs in the [issue tracker](https://github.com/elixir-soap/soap/issues).

## License

Soap is released under the MIT license, see the [LICENSE](https://github.com/elixir-soap/soap/blob/master/LICENSE) file.
