# Soap
[![Build Status](https://travis-ci.org/potok-digital/soap.svg?branch=master)](https://travis-ci.org/potok-digital/soap)
[![Code coverage](https://img.shields.io/coveralls/github/potok-digital/soap.svg?style=flat)](https://coveralls.io/github/potok-digital/soap)
[![Hex version](https://img.shields.io/hexpm/v/soap.svg?style=flat)](https://hex.pm/packages/soap)
[![Hex license](https://img.shields.io/hexpm/l/soap.svg?style=flat)](https://hex.pm/packages/soap)
[![Hex downloads](https://img.shields.io/hexpm/dt/soap.svg?style=flat)](https://hex.pm/packages/soap)

Pure Elixir implementation of SOAP client

## Installation

1) Add `soap` to your deps:

```elixir
def deps do
  [{:soap, "~> 0.2"}]
end
```
2) Add `soap` to the list of application dependencies or just use extra_applications

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
iex(1)> {:ok, wsdl} = Soap.init_model(wsdl_path, :url)
{:ok, parsed_wsdl}

# Call action
iex(2)> {:ok, response} = Soap.call(wsdl, action, params)
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

# Parse body
iex(3)> Soap.Response.parse(response)
%{AddResponse: %{AddResult: "3"}}
```

To add SOAP headers, pass in a `{headers, params}` tuple instead of just params.

```elixir
{:ok, %Soap.Response{}} = Soap.call(wsdl, action, {%{Token: "foo"}, params})
```
