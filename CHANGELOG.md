# Changelog

## v1.0.1
### 🧰 Maintenance
* Improve documentation [#66]

## v1.0.0 🎉🎉🎉
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

## v0.2.1
* Fix crash in parsing by reason of incorrect expression [#56]
* Update library dependencies [#55]

## v0.2.0
* Add MIT license [#53]
* Feat/soap headers [#50]
* Support for different SOAP version for different WSDL files [#49]
* Support WSDL files with WSDL namespace being root [#46]
* Skip params validation if prebuilt XML given [#45]

## v0.1.2
* Update HTTPoison [#44]

## v0.1.1
* Now `Soap.call/4` returns its own response structure `%Soap.Response{body: nil, headers: [], request_url: nil, status_code: nil}`

## v0.1.0
Initial release. A simple low-tested wrapper for sending SOAP requests based on wsdl.
* Parsing base struct from WSDL. `Soap.init_model/2`
* Parsing WSDL from file or url.
* List operations from WSDL.  `Soap.operations/1`
* Execution call requests `Soap.call/4`
