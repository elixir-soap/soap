# Changelog

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
