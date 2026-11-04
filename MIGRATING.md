# Migrating from 1.x to 2.0

2.0 is a rewrite. The API, the result shape and the dependencies all change.

## Quick reference

| 1.x | 2.0 |
|---|---|
| `Soap.init_model(path, :file)` | `Soap.load(path)` |
| `Soap.init_model(url, :url)` | `Soap.load(url)` |
| `Soap.call(wsdl, op, params)` | `Soap.call(client, op, params)` |
| `Soap.call(wsdl, op, {headers, params})` | `Soap.call(client, op, params, headers: headers)` |
| `Soap.call(wsdl, op, params, http_headers)` | `Soap.call(client, op, params, http_headers: http_headers)` |
| `Soap.call(wsdl, op, params, [], http_opts)` | `Soap.call(client, op, params, http_opts: http_opts)` |
| `{:ok, response} = Soap.call(...)`, then `Soap.Response.parse(response)` | `{:ok, result} = Soap.call(...)` |
| `Soap.operations(wsdl)` returned maps | `Soap.operations(client)` returns names |
| `config :soap, :globals, version: "1.2"` | The WSDL decides. Pass `version: "1.2"` if it offers both |
| `config :soap, :globals, http_client: X` | `Soap.load(url, http: X)`, where X implements `Soap.HTTP` |
| `allow_empty_soap_actions: true` | Not needed |
| `soap_version: "1.2"` | `version: "1.2"` on the call, and often not needed |
| `skip_type_imports: true` | Not needed for remote imports, which are skipped by default |
| `raise OperationError` | `{:error, %Soap.Error{reason: {:unknown_operation, name, available}}}` |

Remove `config :soap, :globals` from your configuration. Nothing reads it.

## Results

`Soap.call/4` now returns the decoded result, and it never returns `{:ok, ...}` for a failed call.

```elixir
# 1.x
{:ok, response} = Soap.call(wsdl, "Add", %{intA: 2, intB: 3})
%{AddResponse: %{AddResult: "5"}} = Soap.Response.parse(response)

# 2.0
{:ok, %{"AddResponse" => %{"AddResult" => 5}}} = Soap.call(client, "Add", %{intA: 2, intB: 3})
```

| In a result | 1.x | 2.0 |
|---|---|---|
| Keys | Atoms, with prefixes such as `:"ns1:Result"` | Strings, with no prefixes |
| Numbers, booleans, dates | Strings | Their schema type |
| One repeating element | A map | A list |
| Several repeating elements | A keyword list | A list |
| `xmlns` declarations | Mixed into the data | Dropped |
| An attribute | A plain key | A key starting with `@` |
| Text next to attributes | `"_value"` | `"#text"` |
| `xsi:nil` | A map of attributes | `nil` |

If you need the HTTP status, headers or raw body, use `Soap.request/4`, which returns a `%Soap.Response{}`. Its fields are `status`, `headers`, `body`, `result`, `soap_headers` and `attachments`. 1.x called the status `status_code`.

## Errors

| Situation | 1.x | 2.0 |
|---|---|---|
| SOAP Fault | `{:ok, response}` with a different result shape | `{:error, %Soap.Fault{}}` |
| HTTP error with no Fault | `{:ok, response}`, then a crash in `parse` | `{:error, %Soap.Error{reason: {:http_status, status, body}}}` |
| Reply that isn't XML | A process exit in `parse` | `{:error, %Soap.Error{}}` |
| Params that don't fit the schema | The error text was sent to the server | `{:error, %Soap.Error{reason: {:invalid_param, path, message}}}`, and nothing is sent |
| Missing WSDL file | `MatchError` | `{:error, %Soap.Error{}}` |
| Transport failure | `{:error, reason}` | `{:error, %Soap.Error{reason: {:transport, reason}}}` |

## Requests

Most of these fix bugs, so check them if a server relied on the old output.

- **Field order** now follows the schema. In 1.x, it followed map order.
- **The body wrapper** is now the WSDL's element, such as `tns:Pay`. 1.x used its type's name.
- **Namespaces** now follow the schema, including elements from imported schemas.
- **`SOAPAction`** is now quoted, as the standard requires.
- **Custom HTTP headers** are now added to the standard ones. In 1.x, they replaced all of them.
- **SOAP headers** are now always sent. In 1.x, they vanished unless the WSDL declared a header part.
- **SOAP 1.2** now sends `application/soap+xml`.
- **Newlines and tabs** in values are now kept.
- **Base64 fields** now take raw bytes and encode them. If you were encoding them yourself, stop, or wrap the value in `%Soap.Raw{}`.
- **`dateTime` and `date` values** are now really checked. To send one anyway, pass `validate: false`.

## Imports

1.x fetched whatever a WSDL's imports pointed to. 2.0 follows relative imports, and fetches URLs only from the WSDL's own host. If your WSDL imports from another host:

```elixir
Soap.load(url, allow_imports_from: ["schemas.example.com"])
```

## Dependencies

2.0 uses Saxy for XML and Req for HTTP. `sweet_xml` and `xml_builder` are gone, and `httpoison` is now optional. To keep using HTTPoison, add it to your dependencies and pass `http: Soap.HTTP.HTTPoison`.

Elixir 1.15 or newer is required.
