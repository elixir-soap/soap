# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.1 - 2019-02-14
### 🧰 Maintenance
* Improve documentation [#66]

## v1.0.0 - 2019-02-14 🎉🎉
### 🚀 Features
* Add `Soap.Response.parse/1` [#61]
* Add xsd parsing from external resources [#57]

### 🐛 Bug Fixes
* Fix bug when namespaces is empty [#60]

### 🧰 Maintenance
* Improve readme and documentation [#64]
* Code improvements (dependencies, credo, formatter) [#63]
* Add code coverage [#62]
* Add more documentation and maked some functions as private [#59]
* Add latest major versions elixir to CI [#58]

## v0.2.1 - 2019-02-08
* Fix crash in parsing by reason of incorrect expression [#56]
* Update library dependencies [#55]

## v0.2.0 - 2019-02-05
* Add MIT license [#53]
* Feat/soap headers [#50]
* Support for different SOAP version for different WSDL files [#49]
* Support WSDL files with WSDL namespace being root [#46]
* Skip params validation if prebuilt XML given [#45]

## v0.1.2 - 2018-09-09
* Update HTTPoison [#44]

## v0.1.1 - 2018-01-22
* Now `Soap.call/4` returns its own response structure `%Soap.Response{body: nil, headers: [], request_url: nil, status_code: nil}`

## v0.1.0 - 2018-01-17
Initial release. A simple low-tested wrapper for sending SOAP requests based on wsdl.
* Parsing base struct from WSDL. `Soap.init_model/2`
* Parsing WSDL from file or url.
* List operations from WSDL.  `Soap.operations/1`
* Execution call requests `Soap.call/4`
