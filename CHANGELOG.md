# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 2.0.0 - 2026-11-17

> [!CAUTION]
> **This release breaks compatibility with 1.x.** It's a rewrite with a new API, so code written for 1.x needs changes. The [migration guide](MIGRATING.md) covers each one.

### Breaking changes

- `Soap.init_model/2` is gone. `Soap.load/2` reads the WSDL and returns a client.
- `Soap.call` takes the client and a keyword list of options, instead of positional headers and HTTP options.
- `Soap.call/4` returns the decoded result. A SOAP Fault or a failed request returns `{:error, %Soap.Fault{}}` or `{:error, %Soap.Error{}}`, not `{:ok, response}`.
- Results use string keys, typed values, and lists for elements that can repeat. `Soap.Response.parse/1` is gone.
- `config :soap, :globals` is no longer read. Everything is set per client or per call.
- An unknown operation returns `{:error, %Soap.Error{}}` instead of raising `OperationError`.
- A custom HTTP client must implement `Soap.HTTP`. HTTPoison is no longer used, and Req is the default.
- By default, WSDL imports from other hosts, by absolute path or by `file:` URL are skipped. `:allow_imports_from` allows more hosts.
- Replies with a DOCTYPE, or over 100 MB, are refused.
- Elixir 1.15 or newer is required.

### Added

- `Soap.load/2`, `Soap.call/4`, `Soap.request/4` and `Soap.build_request/4`, configured per client and per call.
- A WSDL model that follows binding, port type, message, part and schema instead of guessing from names.
- Schema-aware requests: order, namespaces, validation, and values formatted by type.
- Schema-aware results: lists stay lists, values are typed, and prefixes are gone.
- `Soap.Fault` and `Soap.Error`, for every failure. Both keep the HTTP reply they came from.
- Call options merge with the client's: HTTP headers, SOAP headers, adapter options and telemetry metadata are combined by name, and `nil` removes one.
- A `:port` option and `Soap.ports/1`, to choose the binding and address when a WSDL offers an operation on several.
- SOAP 1.2 per client, including Faults with subcodes.
- `wsdl:import`, `xsd:include`, `xsd:redefine` and import cycles.
- rpc/encoded requests and replies, with `multiRef` links and `soapenc:Array`.
- WS-Security `UsernameToken`, with a plain password or a digest.
- MTOM in both directions, and SOAP with Attachments.
- `Soap.Raw`, for prebuilt XML.
- A `Soap.HTTP` behaviour for choosing an HTTP client, with Req as the default.
- Telemetry events and a logger, with credentials masked.
- `Soap.Test`, for testing code that calls SOAP services.
- `mix soap.gen`, which generates a typed client from a WSDL.

### Changed

- Results use string keys and no longer create atoms.
- Imports are limited by default: a WSDL can't reach other hosts or read arbitrary files.
- Import host restrictions also apply to scheme-relative URLs and HTTP redirects.
- `:import_root` rejects imports through symlinks below the root directory.
- Loading a WSDL honors `:timeout` and `:connect_timeout`, including its imports.
- Replies with a DOCTYPE are refused.
- Replies are limited to 100 MB, also once decompressed. `:max_reply_size` changes this.
- Most replies decode while they're parsed, with no XML tree in memory.
- Elixir 1.15 or newer is required.

### Removed

- `Soap.init_model`, `Soap.Wsdl`, `Soap.Xsd`, `Soap.Type`, `Soap.Request.Params` and `config :soap, :globals`.
- The `sweet_xml`, `xml_builder` and `httpoison` dependencies.

## v1.1.1 - 2023-08-18

### 🚀 Features

- Add ability to pass arbitrary url in opts for testing [#104]
- Support HTTPoison 2.x [#111]

### 🧰 Maintenance

- Swap to Github Actions [#112]

## v1.1.0 - 2022-04-10

### 🧰 Maintenance

- Add tests for Elixir v1.9.4 and drop versions older than v1.9
- Relax dependencies [#97]
- Misc doc changes [#95]
- Switch from deprecated Mix.Config to Config [#100]
- Add dialyzer and fix type specs [#93]

### 🚀 Features

- Add request options to Soap.init_model [#72]
- Allow blank soap actions on operations [#85]
- Make HTTPoison client configurable [#90]
- Allow string params that happen to be all digit characters [#98]
- Pass HTTP options to XSD and add ability to skip XSD fetching [#103]
- Add support for XML attributes in SOAP request bodies [#99]
- Parsing the document once instead of billion times [#96]

### 🐛 Bug Fixes

- Fix error in WSDL without complex types [#79]
- Fix load xsd files [#80]
- Fix parse WSDL without schema attributes [#81]

## v1.0.1 - 2019-02-14

### 🧰 Maintenance

- Improve documentation [#66]

## v1.0.0 - 2019-02-14 🎉🎉

### 🚀 Features

- Add <code>Soap.Response.parse/1</code> [#61]
- Add xsd parsing from external resources [#57]

### 🐛 Bug Fixes

- Fix bug when namespaces is empty [#60]

### 🧰 Maintenance

- Improve readme and documentation [#64]
- Code improvements (dependencies, credo, formatter) [#63]
- Add code coverage [#62]
- Add more documentation and maked some functions as private [#59]
- Add latest major versions elixir to CI [#58]

## v0.2.1 - 2019-02-08

- Fix crash in parsing by reason of incorrect expression [#56]
- Update library dependencies [#55]

## v0.2.0 - 2019-02-05

- Add MIT license [#53]
- Feat/soap headers [#50]
- Support for different SOAP version for different WSDL files [#49]
- Support WSDL files with WSDL namespace being root [#46]
- Skip params validation if prebuilt XML given [#45]

## v0.1.2 - 2018-09-09

- Update HTTPoison [#44]

## v0.1.1 - 2018-01-22

- Now `Soap.call/4` returns its own response structure `%Soap.Response{body: nil, headers: [], request_url: nil, status_code: nil}`

## v0.1.0 - 2018-01-17

Initial release. A simple low-tested wrapper for sending SOAP requests based on wsdl.

- Parsing base struct from WSDL. <code>Soap.init_model/2</code>
- Parsing WSDL from file or url.
- List operations from WSDL. `Soap.operations/1`
- Execution call requests `Soap.call/4`
