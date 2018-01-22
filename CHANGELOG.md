# Changelog

## v0.1.0
* Now `Soap.call/4` returns its own response structure `%Soap.Response{body: nil, headers: [], request_url: nil, status_code: nil}`

## v0.1.0
Initial release. A simple low-tested wrapper for sending SOAP requests based on wsdl.
* Parsing base struct from WSDL. `Soap.init_model/2`
* Parsing WSDL from file or url.
* List operations from WSDL.  `Soap.operations/1`
* Execution call requests `Soap.call/4`
