# Changelog

## 2.0.0 (unreleased)

A rewrite. See the [migration guide](MIGRATING.md).

### Added

- `Soap.load/2`, `Soap.call/4`, `Soap.request/4` and `Soap.build_request/4`, configured per client and per call.
- A WSDL model that follows binding, port type, message, part and schema instead of guessing from names.
- Schema-aware requests: order, namespaces, validation, and values formatted by type.
- Schema-aware results: lists stay lists, values are typed, and prefixes are gone.
- `Soap.Fault` and `Soap.Error`, for every failure.
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
- Replies with a DOCTYPE are refused.
- Elixir 1.15 or newer is required.

### Removed

- `Soap.init_model`, `Soap.Wsdl`, `Soap.Xsd`, `Soap.Type`, `Soap.Request.Params` and `config :soap, :globals`.
- The `sweet_xml`, `xml_builder` and `httpoison` dependencies.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

- Add `Soap.Response.parse/1` [#61]
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

- Parsing base struct from WSDL. `Soap.init_model/2`
- Parsing WSDL from file or url.
- List operations from WSDL. `Soap.operations/1`
- Execution call requests `Soap.call/4`
