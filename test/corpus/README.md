# SOAP 2.0 test corpus

Real WSDLs, recorded server responses and hand-written edge cases, chosen to cover as many WSDL variants as possible. Soap 2.0 should be built against this corpus.

Harvested and checked on 4 November 2026.

## What is here

| Path | Contents | Size |
|---|---|---|
| `manifest.json` | 93 fixtures with source, commit, license, SHA-256, variants, expected behavior and v1 results | |
| `wsdl/` | 77 real WSDLs, with their imported files, from 9 open-source projects | 844 KB |
| `synthetic/` | Hand-written cases that the harvest did not cover, including security cases | 52 KB |
| `negative/` | Upstream files that are malformed or not valid XML namespaces | 20 KB |
| `golden/node-soap/` | 98 test directories of paired requests and responses, from node-soap | 2.5 MB |
| `recordings/` | 27 real calls to public services, with `index.json` | 284 KB |
| `live_services.json` | 39 public WSDLs with what each needs, plus 20 URLs that no longer work | |
| `licenses/` | License and NOTICE files for every vendored source | |

The tools that produced all of this are in `tools/corpus/`.

## How it was chosen

1. Collected 1,618 candidate files from 17 open-source repositories and 59 public URLs. That gave 1,440 unique WSDLs.
2. Classified each one against 194 variants with `classify.py`.
3. Selected the smallest set that covers every variant, using two examples from different projects where possible. Result: 77 files and 659 KB. 31 rare variants have only one example.
4. Checked operation counts against zeep, an independent client. Zeep loaded 59 of the 77 and agreed on 53. Most of the other 18 are edge cases it rejects or remote imports it couldn't fetch offline. Agreement is useful evidence, but zeep is not the reference.

Counts below cover the whole harvest. Apache CXF supplies 748 of the 1,440 files, so treat them as coverage, not as how common each variant is in production.

## Variant coverage

| Dimension | Variants, with harvest file counts |
|---|---|
| Spec | WSDL 1.1 (1,408), WSDL 2.0 (3) |
| Binding | SOAP 1.1 (978), SOAP 1.2 (171), HTTP GET/POST (42), other such as JMS (116), abstract with no binding (217) |
| Style and use | document/literal (891), rpc/encoded (88), rpc/literal (80), document/encoded (3), misspelled values seen in the wild (`rcp`, `literal`) |
| WSDL prefix | `wsdl:` (678), default namespace (294), default plus alias (434), other (5) |
| Schema prefix | `xsd:` (1,094), default namespace (482), `xs:` (313), `s:` (81), several at once (596), none (43) |
| `soapAction` | present (527), empty (431), missing (203), `soapActionRequired` (1) |
| Operation shape | request-response (1,086), one-way (181), notification (5), solicit-response (1), overloaded name (synthetic) |
| Messages | element parts (951), type parts (219), multi-part (157), zero parts (115), wrapper name differs from operation (335) |
| Headers and faults | input header (82), output header (43), `headerfault` (1), prefix other than `tns` (13), declared faults (258) |
| Imports | `wsdl:import` (253), located `xsd:import` (225), unlocated `xsd:import` (112), `xsd:include` (31), `xsd:redefine` (1), cycles (synthetic) |
| Import locations | relative (397), parent directory (40), absolute URL (53), with query string (1) |
| Services | multiple ports (245), multiple services (80), no service (273), no ports (3), placeholder address (11) |
| Forms | element form qualified (581), unqualified (123), absent (427), local `form` attribute (18), no target namespace (108) |
| Schema constructs | extension, restriction, `choice`, `all`, `any`, `anyAttribute`, groups, `simpleContent`, enumeration, list, union, `nillable`, `minOccurs`, `maxOccurs`, element references, recursive types, mixed content, abstract types, substitution groups, identity constraints |
| Attachments | `mime:multipartRelated` (18), `xmime:expectedContentTypes` (24), base64 (77), hex (7), MTOM policy (1) |
| Policy | WS-Policy (185), WS-SecurityPolicy (147), WS-Addressing (147), reliable messaging (2) |
| Encoding | UTF-8, UTF-8 with BOM, UTF-16 (synthetic), ISO-8859-1, windows-1255, windows-1257, US-ASCII, non-ASCII names |
| Invalid input | not well-formed, empty, unbound prefix, misplaced XML declaration |
| Hostile input | external entity, entity expansion bomb, schema location that targets a metadata service, path traversal (all synthetic) |

### Known gaps

- **WSDL 2.0:** only 3 examples. W3C's test suite URLs no longer respond. Decide whether 2.0 is in scope for Soap 2.0.
- **XSD 1.1 `override`:** no examples found. Probably safe to leave out.
- **XSD edge cases:** the `tefra/xsdata-w3c-tests` repository (MIT) mirrors the W3C schema tests, but it is about 50 MB, so it is not vendored.

## Current library results (v1.1.1)

These are the bars for Soap 2.0 to beat. Reproduce them with `tools/corpus/baseline.exs`.

### Corpus

Across 1,408 WSDL 1.1 files:

| Check | Result |
|---|---|
| `init_model` crashes with default options | 251 (18%) |
| Files with SOAP operations | 1,106 |
| All operations found, default options | 366 (33%) |
| No operations found and no error raised, default options | 595 (54%) |
| All operations found, with `allow_empty_soap_actions` and the right `soap_version` | 947 (86%) |
| Request bodies built (with empty params) | 2,706 |
| Bodies that crash | 389 (14%) |
| Bodies that are not valid XML | 1,086 (40%) |
| Bodies with the wrong wrapper element | 262 (10%) |

Results by variant, with default options. "Good" means valid XML and the right wrapper.

| Variant | Files | Crash | No operations | All operations | Good bodies |
|---|---|---|---|---|---|
| document/literal | 891 | 95 | 452 | 315 | 889 of 2,241 |
| rpc/literal | 80 | 0 | 55 | 22 | 37 of 163 |
| rpc/encoded | 88 | 5 | 58 | 25 | 15 of 86 |
| SOAP 1.2 binding | 171 | 86 | 22 | 62 | 409 of 541 |
| Empty `soapAction` | 431 | 37 | 387 | 1 | 283 of 853 |
| Default plus alias WSDL namespace | 319 | 17 | 235 | 40 | 58 of 684 |
| `wsdl:import` | 215 | 41 | 160 | 12 | 170 of 246 |

The wrapper check only applies where the expected element is known. Body checks use the options that find the most operations.

### Live calls

19 calls went to public services through `Soap.call`, using the real HTTP client with `allow_empty_soap_actions`. **7 gave the right result and 12 failed.** A hand-built request succeeded for 11 of those 12. The twelfth, EORI, got a Fault from the hand-built request too, so it has no reference result.

| Service | Result | Cause seen |
|---|---|---|
| Calculator, SOAP 1.1 | Correct | |
| Calculator, divide by zero | Correct Fault | |
| Calculator, SOAP 1.2 | HTTP 500 Fault | Server didn't recognize the request |
| TempConvert | HTTP 403, then parser `exit` | WSDL gives an `http://` endpoint, and the HTML error page can't be parsed |
| NumberConversion | HTTP 500 Fault | `invalid attribute name 'xmlns:'` |
| CountryInfo, 2 calls | HTTP 500, then parser crash | No usable response |
| InterSystems demo, 2 calls | `OperationError` | Operations not found |
| ArcGIS | HTTP 400, then parser `exit` | |
| Swiss UID | HTTP 500 Fault | `Data_validation_failed` |
| EBI | HTTP 500 Fault | Wrong wrapper element namespace |
| Herong Hello | Crash | `BadMapError` |
| EORI | Crash | `FunctionClauseError` |
| VIES, Brazil central bank (rpc/encoded), SmartBear, CBR, CBR DataSet | Correct | Results keep prefixes and `xmlns` keys |

### Import fetching

`Soap.init_model` follows any schema location in a WSDL. With `ssrf-schema-location.wsdl`, it sent GET requests for `http://169.254.169.254/latest/meta-data/` and `file:///etc/passwd` to its HTTP client (a recording stub in this test). Soap 2.0 must not follow imports across hosts by default.

## Servers

### Public servers that need no key

Use these in a nightly job that doesn't block merges, because they change and go down. `recordings/` holds the replies for offline tests. Keep to one call per case.

| Service | Stack (inferred) | What it adds |
|---|---|---|
| [Calculator](http://www.dneonline.com/calculator.asmx?WSDL) | ASP.NET ASMX | SOAP 1.1 and 1.2, Faults in both versions, HTTP 500 |
| [TempConvert](https://www.w3schools.com/xml/tempconvert.asmx?WSDL) | ASP.NET ASMX | SOAP plus HTTP POST port, `http://` endpoint that refuses plain HTTP calls |
| [NumberConversion](https://www.dataaccess.com/webservicesserver/NumberConversion.wso?WSDL) | DataFlex | Empty `soapAction`, both SOAP versions |
| [CountryInfo](http://webservices.oorsprong.org/websamples.countryinfo/CountryInfoService.wso?WSDL) | DataFlex | Default namespace, arrays |
| [InterSystems demo](https://www.crcind.com/csp/samples/SOAP.Demo.cls?WSDL) | IRIS | DataSet results, HTML error page at HTTP 500 |
| [VIES](https://ec.europa.eu/taxation_customs/vies/checkVatService.wsdl) | Java | Prefixed response elements, empty `soapAction` |
| [EU TIN](https://ec.europa.eu/taxation_customs/tin/checkTinService.wsdl) and [EORI](https://ec.europa.eu/taxation_customs/dds2/eos/validation/services/validation?wsdl) | Java | Faults, non-`.NET` server |
| [Brazil central bank](https://www3.bcb.gov.br/sgspub/JSP/sgsgeral/FachadaWSSGS.wsdl) | Apache Axis | **rpc/encoded with `multiRef` and `href`** |
| [CBR Daily Info](https://www.cbr.ru/DailyInfoWebServ/DailyInfo.asmx?WSDL) | ASP.NET ASMX | **.NET DataSet diffgrams**, 193 KB WSDL |
| [SmartBear sample](http://secure.smartbearsoftware.com/samples/testcomplete14/webservices/Service.asmx?WSDL) | ASP.NET ASMX | Arrays and objects |
| [ArcGIS MapServer](https://services.arcgisonline.com/arcgis/services/World_Imagery/MapServer?wsdl) | Java | 290 KB WSDL with polymorphic types |
| [Swiss UID](https://www.uid-wse.admin.ch/V5.0/PublicServices.svc?wsdl) | WCF | `wsdl:import` split across URLs, BasicHttp |
| [EBI Clustal Omega](https://www.ebi.ac.uk/Tools/services/soap/clustalo?wsdl) | Java | Unqualified elements, strict wrapper checks |
| [Herong Hello](https://www.herongyang.com/Service/Hello_WSDL_11_SOAP.wsdl) | PHP | Simple-type element body, WSDL 2.0 twin file |
| [NOAA NDFD](https://graphical.weather.gov/xml/SOAP_server/ndfdXMLserver.php?wsdl) | PHP | rpc/encoded. WSDL gives `http://localhost` as the endpoint. Returned empty HTTP 500 in testing |

### Public WSDLs that need an account

These are useful for parsing tests only, unless you have credentials. They are large and realistic, but their licenses are unclear, so they are not vendored. `live_services.json` pins their hashes.

Salesforce (enterprise, partner, metadata), eBay (3.9 MB), Workday (3.4 MB), Bing Ads (with and without `singleWsdl`), NetSuite, PayPal, Authorize.net, CyberSource, DHL Express (WS-Security policy), Poland's GUS BIR (MTOM and WS-Addressing), ONVIF, Amazon S3.

### Local servers for what public ones can't provide

No public server without an account was found for **MTOM, WS-Security or WS-Addressing**, and public services can't be used to test failure handling. A Docker Compose stack would fill this gap. Docker is available on this machine, but **none of this stack has been built or run yet**.

| Engine | Current version | Why |
|---|---|---|
| Apache CXF | 4.2.1 | WS-Security with UsernameToken and signatures, MTOM, WS-Addressing, rpc/literal, document bare |
| CoreWCF | 1.9.1 | The .NET stack most enterprise clients meet: WS-Security, MTOM, DataSet |
| node-soap | 1.14.0 | Fast to start, shares a license and test cases with `golden/node-soap` |
| PHP `SoapServer` | Bundled with PHP | Stable rpc/encoded server with arrays and `href` references |
| Apache Axis 1.4 | Legacy | The rpc/encoded `multiRef` format older enterprise services still produce |

Spyne (LGPL) and gSOAP (GPL or commercial) are alternatives. Running them in a container is fine, but their code must not be vendored here.

## Proposed test layers

| Layer | Runs | Uses | Checks |
|---|---|---|---|
| Parser | Every commit | `wsdl/`, `synthetic/`, `negative/` | Right operations, ports, styles, types and errors for each manifest entry |
| Golden | Every commit | `golden/node-soap/`, php-src `ext/soap/tests/interop` (213 tests) and `bugs` (144 tests) | Request bytes match after XML normalization, and responses decode as expected |
| Replay | Every commit | `recordings/` | Faults, multiRef, DataSet, HTML errors and empty bodies decode correctly |
| Wire | Every commit | Local Bandit server | See the list below |
| Property | Every commit | Generated values against corpus schemas | Encoding then decoding gives back the same value, and output is schema-valid |
| Whole corpus | Nightly | All 1,440 harvested WSDLs | No crash, and the numbers above only improve |
| Interop | Nightly | Docker stack | Real calls to each engine, across every style, version and security option |
| Live | Nightly, doesn't block merges | Public services | Real calls still work |

**Wire scenarios to build:** HTTP 202 with an empty body for one-way calls, Fault at HTTP 200, 400 and 500, SOAP 1.2 Fault with subcodes, HTML gateway errors, truncated bodies, gzip, chunked responses, redirects on POST, BOM in responses, ISO-8859-1 responses, MTOM multipart responses, slow responses and timeouts, and responses with many unique tag names to prove no atoms are created.

## Licensing

Vendored files come only from permissive projects: MIT, BSD-3-Clause and Apache-2.0. See `licenses/`. Some fixtures in those projects may themselves be copied from third-party services, so review this before publishing the corpus. `mix.exs` already leaves `test/` out of the Hex package.

Harvested but deliberately not vendored: `hooklift/gowsdl` (MPL-2.0), `onvif/specs` (custom license), `fiorix/wsdl2go` (license not detected by GitHub) and `reficio/soap-ws` (no license).

## Refreshing

```bash
python3 tools/corpus/classify.py CORPUS_DIR classified.json
```

```bash
python3 tools/corpus/expected.py CORPUS_DIR classified.json expected.json
```

```bash
mix run --no-start tools/corpus/baseline.exs CORPUS_DIR expected.json baseline.jsonl
```

`CORPUS_DIR` is a scratch directory holding the clones and downloads, in `oss/<owner>__<repo>/` and `live/<id>/body`. It stays out of the repository.
