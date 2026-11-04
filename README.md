# Soap

[![Module Version](https://img.shields.io/hexpm/v/soap.svg)](https://hex.pm/packages/soap)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/soap/)
[![License](https://img.shields.io/hexpm/l/soap.svg)](https://github.com/elixir-soap/soap/blob/master/LICENSE.md)

A SOAP client for Elixir. It reads a WSDL, checks your params against its schema, and gives you back plain Elixir data shaped by that schema.

```elixir
{:ok, client} = Soap.load("http://www.dneonline.com/calculator.asmx?WSDL")

Soap.operations(client)
#=> ["Add", "Subtract", "Multiply", "Divide"]

Soap.call(client, "Add", %{intA: 2, intB: 3})
#=> {:ok, %{"AddResponse" => %{"AddResult" => 5}}}
```

Coming from 1.x? See the [migration guide](MIGRATING.md).

## Installation

```elixir
def deps do
  [
    {:soap, "~> 2.0"}
  ]
end
```

There's nothing to configure. Options go on the client or the call, so one application can talk to any number of services, in either SOAP version.

## Loading a service

```elixir
{:ok, client} = Soap.load("priv/service.wsdl")
{:ok, client} = Soap.load("https://example.com/service?wsdl", timeout: 10_000)
{:ok, client} = Soap.from_string(wsdl_xml)
```

Options you pass here become defaults for every call. A call's own options win.

### Imports

A WSDL is often loaded from somewhere you don't control, so imports are limited by default.

| Reference in a document | From a local file | From a URL |
|---|---|---|
| Relative path | Read | Fetched from the same host |
| `http` or `https` URL | Skipped | Fetched from the same host only |
| Absolute path, `file:`, others | Skipped | Skipped |

- `allow_imports_from: ["schemas.example.com"]` or `allow_imports_from: :all` allows more hosts.
- `import_root: "priv/wsdl"` keeps local imports inside a directory. Without it, a local WSDL can import from parent directories.
- `client.service.unresolved_imports` lists what was skipped, and why.
- An import that's allowed but can't be read is an error. `ignore_failed_imports: true` accepts a partial model instead.

## Calling

```elixir
Soap.call(client, "CreateOrder", %{
  "Customer" => %{"Name" => "Ann", "Phones" => ["555-1", "555-2"]},
  "Total" => %{"@currency" => "EUR", "#text" => Decimal.new("10.50")},
  "Date" => ~D[2026-11-04],
  "Note" => nil
})
```

- Params can be a map, a keyword list, or a list of `{name, value}` or `{name, attributes, value}` tuples. Names can be atoms or strings.
- Elements go out in the order and namespaces the schema requires.
- A list repeats the element.
- `"@name"` is an attribute, and `"#text"` is an element's text next to its attributes.
- `nil` leaves the element out, or sends `xsi:nil` if the schema allows that.
- Values go out in the form their type needs, including `Date`, `DateTime` and `Decimal`. Base64 and hex fields take raw bytes.

### Validation

A value that can't fit its type, or an element the schema doesn't allow, returns an error and nothing gets sent:

```elixir
Soap.call(client, "Add", %{intA: "two"})
#=> {:error, %Soap.Error{reason: {:invalid_param, "Add/intA", "\"two\" isn't a valid int"}}}
```

Missing required elements are allowed, because servers often accept less than their WSDL says. `validate: false` turns validation off.

### Options

| Option | Meaning |
|---|---|
| `:endpoint` | Send here instead of the address in the WSDL |
| `:version` | `"1.1"` or `"1.2"`, when the WSDL offers both |
| `:input` | The input's name, to choose between overloaded operations |
| `:headers` | SOAP headers, in the same forms as params |
| `:http_headers` | Extra HTTP headers. One with a standard header's name replaces it |
| `:wsse` | WS-Security credentials |
| `:mtom` | Send every base64 field as an attachment |
| `:attachments` | Extra `%Soap.Attachment{}` parts |
| `:validate` | Check params against the schema. Defaults to true |
| `:timeout`, `:connect_timeout` | In milliseconds |
| `:follow_redirects` | Follow redirects on calls. Defaults to false |
| `:http`, `:http_opts` | The HTTP adapter and its options |

## Results

```elixir
{:ok, %{"GetOrderResponse" => order}} = Soap.call(client, "GetOrder", %{id: 7})

order
#=> %{
#=>   "Id" => 7,
#=>   "Paid" => true,
#=>   "Created" => ~U[2026-11-04 10:00:00Z],
#=>   "Lines" => [%{"Sku" => "A-1", "Quantity" => 2}],
#=>   "Total" => %{"@currency" => "EUR", "#text" => "10.50"}
#=> }
```

- Keys are strings, so a reply can't create atoms. Prefixes are dropped, so a server changing its prefix changes nothing.
- An element that can repeat is always a list, even with one item.
- Values take their schema type. A value that doesn't parse stays a string.
- `xsd:decimal` stays a string, so no precision is lost. Call `Decimal.new/1` if you want a `Decimal`.
- `xsi:nil` is `nil`.
- `rpc/encoded` links (`multiRef`, `href`) are followed, and `soapenc:Array` becomes a list.

With no schema, as in `Soap.decode_response(nil, nil, status, headers, body)`, a repeated element is a list, a single one isn't, and values are strings.

For the HTTP status, raw body, SOAP headers and attachments, use `Soap.request/4`. To see what would be sent, use `Soap.build_request/4`.

## Errors

```elixir
case Soap.call(client, "Pay", params) do
  {:ok, result} -> result
  {:error, %Soap.Fault{code: code, message: message}} -> {:rejected, code, message}
  {:error, %Soap.Error{reason: {:transport, reason}}} -> {:unreachable, reason}
  {:error, %Soap.Error{reason: reason}} -> {:failed, reason}
end
```

Bad input never raises or exits. A SOAP Fault is reported the same way at any HTTP status, in either SOAP version. `Soap.call!/4` raises these as exceptions instead.

## WS-Security

```elixir
token = Soap.WSSE.username_token("ann", "secret")
Soap.call(client, "GetOrders", %{}, wsse: token)

token = Soap.WSSE.username_token("ann", "secret", digest: true, timestamp: 300)
```

This supports `UsernameToken` with a plain password or a digest. Message signing and encryption aren't supported. Send plain passwords over HTTPS only.

## Attachments

```elixir
# MTOM: every base64 field goes as a binary part.
Soap.call(client, "Upload", %{"File" => bytes}, mtom: true)

# MTOM for one field, with a content type.
Soap.call(client, "Upload", %{"File" => %Soap.Attachment{data: bytes, content_type: "image/png"}})

# SOAP with Attachments: extra parts with no reference in the XML.
Soap.call(client, "Upload", %{}, attachments: [%Soap.Attachment{data: bytes}])
```

MTOM replies resolve into the result automatically. Other parts are in `Soap.request/4`'s `attachments`.

## Raw XML

```elixir
Soap.call(client, "Send", %{"Document" => %Soap.Raw{xml: prebuilt_fragment}})
Soap.call(client, "Send", params, headers: [%Soap.Raw{xml: custom_header}])
```

Raw XML goes out unchecked and unescaped, so never build it from untrusted input.

## HTTP clients

Req is the default, and you can pass it options:

```elixir
Soap.load(url, http_opts: [req: [connect_options: [proxy: {:http, "proxy", 3128, []}]]])
```

To use another client, implement `Soap.HTTP` and pass it as `:http`. For HTTPoison:

```elixir
defmodule MyApp.SoapHTTP do
  @behaviour Soap.HTTP

  @impl true
  def request(method, url, headers, body, opts) do
    options = [
      recv_timeout: opts[:timeout] || 5_000,
      follow_redirect: opts[:follow_redirects] || false
    ]

    case HTTPoison.request(method, url, IO.iodata_to_binary(body), headers, options) do
      {:ok, %HTTPoison.Response{status_code: status, headers: headers, body: body}} ->
        {:ok, %{status: status, headers: headers, body: body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end
end

Soap.load(url, http: MyApp.SoapHTTP)
```

## Generating a client

```bash
mix soap.gen priv/calculator.wsdl --module MyApp.Calculator
```

This writes a module with one documented, typed function per operation:

```elixir
{:ok, client} = MyApp.Calculator.client()
MyApp.Calculator.add(client, %{"intA" => 2, "intB" => 3})
```

## Testing your code

`Soap.Test` answers calls with no network:

```elixir
{:ok, client} =
  Soap.Test.client("priv/calculator.wsdl", fn request ->
    assert request.operation == "Add"
    assert request.params == %{"intA" => "2", "intB" => "3"}
    Soap.Test.reply("AddResponse", %{"AddResult" => 5}, namespace: "http://tempuri.org/")
  end)

assert {:ok, %{"AddResponse" => %{"AddResult" => 5}}} = Soap.call(client, "Add", %{intA: 2, intB: 3})
```

Handlers can also return `Soap.Test.fault("soap:Server", "boom")`, `{status, body}` or `{:error, :timeout}`.

## Telemetry

Each call emits `[:soap, :request, :start | :stop | :exception]`. Metadata holds the operation, version, URL, status and outcome, with credentials removed. To log calls:

```elixir
Soap.Telemetry.attach_default_logger(level: :info)
```

See `Soap.Telemetry`.

## Compatibility

- SOAP 1.1 and 1.2.
- WSDL 1.1, in document/literal, rpc/literal and rpc/encoded. WSDL 2.0 returns a clear error.
- WSDLs split across files with `wsdl:import`, `xsd:import` and `xsd:include`.
- XML in UTF-8, UTF-16 and ISO-8859-1.

Replies containing a DOCTYPE are refused, so external entities and entity bombs can't apply.

## Testing this library

The suite in `test/conformance/` runs against 1,400 real-world WSDLs, recorded replies, PHP's and node-soap's test suites, a raw socket server that sends broken replies, public services, and real servers in Docker: Apache CXF, PHP `SoapServer` and node-soap. See [test/corpus/README.md](test/corpus/README.md).

```bash
mix test
```

```bash
docker compose -f test/interop/docker-compose.yml up -d --build --wait
```

```bash
mix test --only interop
```

## Copyright and License

Copyright (c) 2017 Petr Stepchenko

This work is free. You can redistribute it and/or modify it under the terms of the MIT License. See the [LICENSE.md](./LICENSE.md) file for more details.
