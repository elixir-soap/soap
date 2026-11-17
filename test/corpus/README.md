# SOAP 2.0 test corpus

Real WSDLs, recorded server responses and hand-written edge cases, chosen to cover as many WSDL variants as possible. Soap 2.0 is built against this corpus.

Harvested and checked on 4 November 2026.

## What is here

| Path | Contents | Size |
|---|---|---|
| `manifest.json` | 93 fixtures with source, commit, license, SHA-256, variants, expected behavior and v1 results | |
| `wsdl/` | 77 real WSDLs, with their imported files, from 9 open-source projects | 844 KB |
| `synthetic/` | Hand-written cases that the harvest did not cover, including security cases | 52 KB |
| `negative/` | Upstream files that are malformed or not valid XML namespaces | 20 KB |
| `golden/node-soap/` | 98 test directories of paired requests and responses, from node-soap | 2.5 MB |
| `golden/php-interop/` | 315 envelopes extracted from php-src's SOAPBuilders tests | 1.2 MB |
| `recordings/` | 27 real calls to public services, with `index.json` | 284 KB |
| `live_services.json` | 39 public WSDLs with what each needs, plus 20 URLs that no longer work | |
| `live_calls.json` | Read-only calls for the live layer | |
| `known_failures/` | Checks each driver is known to fail | |
| `scores/` | Whole-corpus score floors for each driver | |
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

## Results

### 1.1.1 against 2.0

Measured across the same files and servers. 1.x is at the `v1.1.1` tag.

| Check | 1.1.1 | 2.0 |
|---|---|---|
| WSDL loads with default options, of 1,416 | 1,164 | 1,273 |
| All operations found, default options, of 1,112 | 372 | 987 |
| All operations found, tolerant options, of 1,112 | 953 | 1,112 |
| Valid request, right wrapper, with empty params, of 2,886 | 1,144 | 2,884 |
| Calls to public services giving the right result | 7 of 19 | 15 of 15 (a shorter list) |
| Conformance checks at the time of writing | 437 of 850 | All 1,164, with no known failures |

The 143 files that don't load with default options have an import that can't be read. That's an error by default, and `ignore_failed_imports: true` accepts them. "Tolerant" means that option for 2.0, and `allow_empty_soap_actions` with the right `soap_version` for 1.1.1.

### Import fetching

1.1.1's `Soap.init_model` followed any schema location in a WSDL. With `ssrf-schema-location.wsdl`, it sent GET requests for `http://169.254.169.254/latest/meta-data/` and `file:///etc/passwd` to its HTTP client (a recording stub in this test). 2.0 skips both and reports them.

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

No public server without an account was found for MTOM, WS-Security or WS-Addressing, and public services can't be used to test failure handling. `test/interop/` runs real ones in Docker:

| Engine | What it covers |
|---|---|
| Apache CXF 4.2.1 | Document and rpc/literal, SOAP 1.2, MTOM in both directions, WS-Security with plain and digest passwords |
| PHP `SoapServer` | rpc/encoded, typed scalars, `soapenc:Array`, shared references |
| node-soap 1.14.0 | Document/literal round trips, WS-Security with plain and digest passwords |

WS-Addressing isn't built in, and CoreWCF and Axis 1.4 aren't in the stack.

## Conformance suite

The suite in `test/conformance/` runs through a driver, which keeps the checks independent of the API.

```bash
mix test
```

| Layer | Runs | File | Checks |
|---|---|---|---|
| Parser | Every commit | `parser_test.exs` | Operations, endpoints, envelope, wrapper, action and content type for each manifest entry, against facts from `tools/corpus/add_truth.py` |
| Golden | Every commit | `golden_test.exs` | Requests match node-soap's after normalization, and responses hold the expected values. Where 2.0 deliberately differs, the test names the sample and says why |
| PHP interop | Every commit | `php_interop_test.exs` | 314 replies from PHP's SOAPBuilders suite decode to clean data |
| Replay | Every commit | `replay_test.exs` | Recorded Faults, multiRef, DataSet, HTML errors and empty bodies decode correctly, with clean keys |
| Wire | Every commit | `wire_test.exs` | The real HTTP client against a raw socket server: chunked, gzip, BOM, encodings, MTOM, Faults, broken and slow replies, hostile XML, atom growth |
| Faults | Every commit | `faults_test.exs` | One check for each runtime fault from the 1.1.1 audit |
| Property | Every commit | `property_test.exs` | Any text survives both directions, and decoding any bytes returns a result |
| Whole corpus | Nightly | `whole_corpus_test.exs` | All harvested WSDLs, against score floors in `scores/` |
| Interop | Nightly | `interop_test.exs` | Real calls to Apache CXF, PHP and node-soap in Docker |
| Live | Nightly, doesn't block merges | `live_test.exs` | Read-only calls listed in `live_calls.json` |

`harness_test.exs` tests the tools themselves.

```bash
tools/corpus/harvest.sh /tmp/corpus
```

```bash
CORPUS_DIR=/tmp/corpus mix test --only nightly
```

```bash
mix test --only live
```

```bash
docker compose -f test/interop/docker-compose.yml up -d --build --wait
```

```bash
mix test --only interop
```

### The ratchet

`known_failures/<driver>.json` lists each check a driver is known to fail, with the reason it failed.

- A check that fails and isn't listed fails the build. It's a regression or a new gap.
- A check that passes but is still listed also fails the build, so progress is locked in as soon as it happens.

After a deliberate change, rewrite the list and review its diff:

```bash
CONFORMANCE_UPDATE=1 mix test
```

### Not covered

- **php-src request checks:** the `.phpt` inputs are PHP code, so only their replies are used.
- **Schema-valid output:** properties cover text, not whether generated requests validate against their schema.
- **WS-Security signing and encryption, and WS-Addressing:** not implemented.
- **WSDL 2.0:** returns a clear error.

## Licensing

Vendored files come only from permissive projects: MIT, BSD-3-Clause and Apache-2.0. See `licenses/`. Some fixtures in those projects may themselves be copied from third-party services, so review this before publishing the corpus. `mix.exs` already leaves `test/` out of the Hex package.

Harvested but deliberately not vendored: `hooklift/gowsdl` (MPL-2.0), `onvif/specs` (custom license), `fiorix/wsdl2go` (license not detected by GitHub) and `reficio/soap-ws` (no license).

## Refreshing

`harvest.sh` downloads the full harvest and classifies it. After changing fixtures in `manifest.json`, recompute their facts:

```bash
python3 tools/corpus/add_truth.py test/corpus
```

The harvest directory stays out of the repository.
