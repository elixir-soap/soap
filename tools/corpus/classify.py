#!/usr/bin/env python3
"""Classify WSDL files into variant features. usage: classify.py ROOT OUT.json
Walks ROOT, parses every candidate file, emits one record per file."""
import json, os, re, sys, hashlib
import xml.etree.ElementTree as ET

W11 = 'http://schemas.xmlsoap.org/wsdl/'
W20 = 'http://www.w3.org/ns/wsdl'
S11 = 'http://schemas.xmlsoap.org/wsdl/soap/'
S12 = 'http://schemas.xmlsoap.org/wsdl/soap12/'
HTTPB = 'http://schemas.xmlsoap.org/wsdl/http/'
MIME = 'http://schemas.xmlsoap.org/wsdl/mime/'
XSD = 'http://www.w3.org/2001/XMLSchema'
ENC = 'http://schemas.xmlsoap.org/soap/encoding/'
XMIME = {'http://www.w3.org/2005/05/xmlmime', 'http://www.w3.org/2004/11/xmlmime', 'http://www.w3.org/2004/06/xmlmime'}


def q(ns, t):
    return '{%s}%s' % (ns, t)


def local(t):
    return t.split('}', 1)[-1]


def nsof(t):
    return t[1:].split('}', 1)[0] if t.startswith('{') else ''


def classify(path):
    raw = open(path, 'rb').read()
    f = set()
    size = len(raw)
    head = raw[:4096]
    if raw[:3] == b'\xef\xbb\xbf':
        f.add('enc:utf8-bom')
    if raw[:2] in (b'\xff\xfe', b'\xfe\xff'):
        f.add('enc:utf16')
    m = re.search(rb'encoding=["\']([\w-]+)', head)
    if m and m.group(1).lower() not in (b'utf-8', b'utf8'):
        f.add('enc:' + m.group(1).decode().lower())
    if b'<!DOCTYPE' in raw[:8192]:
        f.add('dtd:doctype')
    try:
        ns_decls = []
        root = None
        import io
        for ev, el in ET.iterparse(io.BytesIO(raw), events=('start-ns', 'start')):
            if ev == 'start-ns':
                ns_decls.append(el)
            elif root is None:
                root = el
        root = ET.fromstring(raw)
    except Exception as e:
        msg = str(e)
        bad = 'bad:unbound-prefix' if 'unbound prefix' in msg else 'bad:decl-not-at-start' if 'declaration not at start' in msg else 'bad:empty' if 'no element found' in msg and size < 40 else 'bad:not-well-formed'
        return {'kind': 'malformed', 'features': [bad], 'size': size, 'error': msg[:120]}
    rns, rl = nsof(root.tag), local(root.tag)
    if rl == 'description' and rns == W20:
        kind = 'wsdl20'
    elif rl == 'definitions' and rns == W11:
        kind = 'wsdl11'
    else:
        return {'kind': 'other', 'root': root.tag[:100], 'features': [], 'size': size}

    if size > 1_000_000:
        f.add('size:over-1mb')
    elif size > 100_000:
        f.add('size:100kb-1mb')
    # prefixes
    wpre = {p for p, u in ns_decls if u == rns}
    if '' in wpre and len(wpre) > 1:
        f.add('prefix:wsdl-default-and-alias')
    elif '' in wpre:
        f.add('prefix:wsdl-default')
    elif wpre <= {'wsdl'}:
        f.add('prefix:wsdl-wsdl')
    else:
        f.add('prefix:wsdl-other')
    spre = {p for p, u in ns_decls if u == XSD}
    for p in spre:
        f.add('prefix:xsd-' + (p if p in ('xsd', 'xs', 's') else ('default' if p == '' else 'other')))
    if len(spre) > 1:
        f.add('prefix:xsd-multiple')
    if not spre:
        f.add('prefix:xsd-none')
    if any(p in ('soap12', 'wsoap12', 'soap') and u == S12 for p, u in ns_decls) and False:
        pass
    if any(p == 'soap' and u == S12 for p, u in ns_decls):
        f.add('prefix:soap-means-soap12')

    if kind == 'wsdl20':
        f.add('wsdl:2.0')
        wsoap = 'http://www.w3.org/ns/wsdl/soap'
        for el in root.iter():
            if local(el.tag) == 'binding' and nsof(el.tag) == W20:
                t = el.get('type', '')
                f.add('wsdl20:binding-soap' if t == wsoap else 'wsdl20:binding-http' if 'http' in t else 'wsdl20:binding-other')
                if el.get('{%s}version' % wsoap) == '1.1':
                    f.add('wsdl20:soap11')
        return {'kind': kind, 'features': sorted(f), 'size': size}

    f.add('wsdl:1.1')
    # imports
    wimports = root.findall(q(W11, 'import'))
    if wimports:
        f.add('import:wsdl')
    for ty in root.findall(q(W11, 'types')):
        schemas = ty.findall(q(XSD, 'schema'))
        if len(schemas) > 1:
            f.add('types:multiple-inline-schemas')
        if not schemas:
            f.add('types:empty-or-nonxsd')
    if not root.findall(q(W11, 'types')):
        f.add('types:none')
    locs = []
    for s in root.iter(q(XSD, 'schema')):
        efd = s.get('elementFormDefault')
        f.add('form:element-' + (efd or 'absent'))
        afd = s.get('attributeFormDefault')
        if afd:
            f.add('form:attribute-' + afd)
        if not s.get('targetNamespace'):
            f.add('schema:no-target-namespace')
        for k in ('import', 'include', 'redefine', 'override'):
            for i in s.findall(q(XSD, k)):
                sl = i.get('schemaLocation')
                if k == 'import' and not sl:
                    f.add('import:xsd-no-location')
                elif k == 'import':
                    f.add('import:xsd-located')
                else:
                    f.add('import:xsd-' + k)
                if sl:
                    locs.append(sl)
    for i in wimports:
        if i.get('location'):
            locs.append(i.get('location'))
    for l in locs:
        f.add('location:absolute-url' if re.match(r'https?:', l) else 'location:query-string' if '?' in l else 'location:parent-dir' if l.startswith('..') else 'location:relative')

    # messages / parts
    msgs = {}
    for m in root.findall(q(W11, 'message')):
        parts = m.findall(q(W11, 'part'))
        msgs[m.get('name')] = parts
        if len(parts) == 0:
            f.add('msg:zero-parts')
        if len(parts) > 1:
            f.add('msg:multi-part')
        for p in parts:
            if p.get('element'):
                f.add('part:element')
            if p.get('type'):
                f.add('part:type')

    # portType ops
    for pt in root.findall(q(W11, 'portType')):
        seen = {}
        for op in pt.findall(q(W11, 'operation')):
            kids = [local(c.tag) for c in op if nsof(c.tag) == W11 and local(c.tag) in ('input', 'output')]
            mep = {('input',): 'one-way', ('input', 'output'): 'request-response', ('output',): 'notification', ('output', 'input'): 'solicit-response'}.get(tuple(kids), 'unknown')
            f.add('mep:' + mep)
            if op.find(q(W11, 'fault')) is not None:
                f.add('op:fault-declared')
            if op.get('parameterOrder'):
                f.add('op:parameterOrder')
            seen[op.get('name')] = seen.get(op.get('name'), 0) + 1
            inp = op.find(q(W11, 'input'))
            if inp is not None:
                mn = (inp.get('message') or '').split(':')[-1]
                ps = msgs.get(mn, [])
                if len(ps) == 1 and ps[0].get('element'):
                    el = ps[0].get('element').split(':')[-1]
                    f.add('wrapper:element-eq-op' if el == op.get('name') else 'wrapper:element-ne-op')
        if any(v > 1 for v in seen.values()):
            f.add('op:overloaded')

    # bindings
    if not root.findall(q(W11, 'binding')):
        f.add('binding:none-abstract')
    for b in root.findall(q(W11, 'binding')):
        kinds = set()
        for c in b:
            n = nsof(c.tag)
            if local(c.tag) == 'binding':
                kinds.add(n)
                if n in (S11, S12):
                    f.add('binding:' + ('soap11' if n == S11 else 'soap12'))
                    ds = c.get('style')
                    tr = c.get('transport') or ''
                    if ds is None:
                        f.add('style:default-absent')
                    if tr and 'soap/http' not in tr:
                        f.add('transport:non-http')
                elif n == HTTPB:
                    f.add('binding:http-get-post')
                else:
                    f.add('binding:other')
        soapns = S11 if S11 in kinds else S12 if S12 in kinds else None
        bstyle = None
        for c in b:
            if local(c.tag) == 'binding' and nsof(c.tag) in (S11, S12):
                bstyle = c.get('style') or 'document'
        for op in b.findall(q(W11, 'operation')):
            if soapns is None:
                continue
            so = op.find(q(soapns, 'operation'))
            style = (so.get('style') if so is not None else None) or bstyle or 'document'
            if so is not None and so.get('style') and bstyle and so.get('style') != bstyle:
                f.add('style:op-overrides-binding')
            if so is None or so.get('soapAction') is None:
                f.add('action:missing')
            elif so.get('soapAction') == '':
                f.add('action:empty')
            elif so.get('soapAction'):
                f.add('action:present')
            if so is not None and so.get('soapActionRequired'):
                f.add('action:required-attr')
            for sect in ('input', 'output'):
                io_ = op.find(q(W11, sect))
                if io_ is None:
                    continue
                body = io_.find(q(soapns, 'body'))
                if body is not None:
                    use = body.get('use') or 'literal'
                    f.add('combo:%s/%s' % (style, use))
                    if body.get('parts') is not None:
                        f.add('body:parts-attr')
                    if body.get('namespace'):
                        f.add('body:namespace-attr')
                    if body.get('encodingStyle'):
                        f.add('body:encodingStyle')
                if io_.find(q(soapns, 'header')) is not None:
                    f.add('header:declared-' + sect)
                    if io_.find(q(soapns, 'header')).find(q(soapns, 'headerfault')) is not None:
                        f.add('header:headerfault')
                    hm = (io_.find(q(soapns, 'header')).get('message') or '')
                    if ':' in hm and hm.split(':')[0] != 'tns':
                        f.add('header:message-prefix-not-tns')
                if io_.find(q(MIME, 'multipartRelated')) is not None:
                    f.add('attach:mime-multipart-related')
                if io_.find(q(MIME, 'content')) is not None:
                    f.add('attach:mime-content')
            if op.find(q(W11, 'fault')) is not None:
                f.add('binding:fault-declared')

    # services
    svcs = root.findall(q(W11, 'service'))
    if not svcs:
        f.add('service:none')
    if len(svcs) > 1:
        f.add('service:multiple')
    for s in svcs:
        ports = s.findall(q(W11, 'port'))
        if len(ports) > 1:
            f.add('service:multi-port')
        if not ports:
            f.add('service:no-ports')
        for p in ports:
            for a in p:
                if local(a.tag) == 'address':
                    loc = a.get('location') or ''
                    if nsof(a.tag) in (S11, S12):
                        if not loc or 'REPLACE' in loc:
                            f.add('address:placeholder-or-empty')
                        elif loc.startswith('https'):
                            f.add('address:https')
                    if nsof(a.tag) not in (S11, S12, HTTPB):
                        f.add('address:other-ext')

    # schema constructs + extensions
    uses_xsd = {'base64Binary': 'xsd:base64Binary', 'hexBinary': 'xsd:hexBinary', 'dateTime': 'xsd:dateTime', 'decimal': 'xsd:decimal', 'duration': 'xsd:duration', 'QName': 'xsd:QName', 'anyType': 'xsd:anyType', 'anyURI': 'xsd:anyURI', 'integer': 'xsd:integer', 'long': 'xsd:long', 'boolean': 'xsd:boolean', 'date': 'xsd:date', 'time': 'xsd:time', 'float': 'xsd:float', 'double': 'xsd:double', 'NMTOKEN': 'xsd:NMTOKEN'}
    named_types = {}
    for el in root.iter():
        n, l = nsof(el.tag), local(el.tag)
        for an, av in el.attrib.items():
            if nsof(an) in XMIME:
                f.add('attach:xmime-content-type')
            if local(an) == 'arrayType' and nsof(an) == W11:
                f.add('enc:soapenc-array')
            if local(an) == 'Action' and 'addressing' in nsof(an):
                f.add('wsa:action-attr')
        if n == 'http://schemas.xmlsoap.org/ws/2004/09/policy' or n == 'http://www.w3.org/ns/ws-policy':
            f.add('policy:ws-policy')
        if 'securitypolicy' in n:
            f.add('policy:ws-security')
        if 'mtom' in n.lower() or (l == 'OptimizedMimeSerialization'):
            f.add('policy:mtom')
        if 'addressing' in n and n:
            f.add('wsa:used')
        if 'ws-rx' in n or 'reliablemessaging' in n.lower():
            f.add('policy:reliable-messaging')
        if l == 'documentation' and n == W11:
            f.add('doc:wsdl-documentation')
        if n == 'http://java.sun.com/xml/ns/jaxws' or n == 'http://java.sun.com/xml/ns/jaxb':
            f.add('ext:jaxws-binding')
        if n != XSD:
            continue
        if l in ('choice', 'all', 'any', 'anyAttribute', 'attributeGroup', 'group', 'simpleContent', 'list', 'union', 'notation', 'unique', 'key', 'keyref'):
            f.add('xs:' + l)
        if l == 'extension':
            f.add('xs:extension')
        if l == 'restriction':
            base = local_q(el.get('base'))
            if base == 'Array':
                f.add('enc:soapenc-array')
            f.add('xs:restriction')
        if l == 'complexContent':
            f.add('xs:complexContent')
        if l == 'enumeration':
            f.add('xs:enumeration')
        if l == 'pattern':
            f.add('xs:pattern')
        if l == 'attribute':
            f.add('xs:attribute')
        if l == 'element':
            if el.get('substitutionGroup'):
                f.add('xs:substitutionGroup')
            if el.get('abstract') == 'true':
                f.add('xs:abstract-element')
            if el.get('nillable') == 'true':
                f.add('xs:nillable')
            if el.get('ref'):
                f.add('xs:element-ref')
            if el.get('form'):
                f.add('xs:local-form-attr')
            if el.get('default') is not None or el.get('fixed') is not None:
                f.add('xs:element-default-or-fixed')
            mo = el.get('maxOccurs')
            if mo == 'unbounded' or (mo and mo.isdigit() and int(mo) > 1):
                f.add('xs:maxOccurs-many')
            if el.get('minOccurs') == '0':
                f.add('xs:minOccurs-0')
            if el.get('type') is None and el.get('ref') is None and el.find(q(XSD, 'complexType')) is not None:
                f.add('xs:anonymous-complex')
            t = local_q(el.get('type'))
            if t in uses_xsd:
                f.add(uses_xsd[t])
        if l == 'complexType':
            if el.get('abstract') == 'true':
                f.add('xs:abstract-type')
            if el.get('mixed') == 'true':
                f.add('xs:mixed')
            nm = el.get('name')
            if nm:
                named_types[nm] = el
    # recursion: named type referencing itself directly
    for nm, el in named_types.items():
        for d in el.iter(q(XSD, 'element')):
            if local_q(d.get('type')) == nm:
                f.add('xs:recursive-type')
                break
    # .NET dataset style
    if any(local(e.tag) == 'element' and nsof(e.tag) == XSD and (e.get('ref') or '').split(':')[-1] == 'schema' for e in root.iter()):
        f.add('xs:dotnet-diffgram')
    # non-ascii names
    for m in root.findall(q(W11, 'message')):
        if not (m.get('name') or '').isascii():
            f.add('name:non-ascii')
    return {'kind': kind, 'features': sorted(f), 'size': size, 'locations': locs[:40]}


def local_q(v):
    return v.split(':')[-1] if v else None


def is_candidate(fn):
    l = fn.lower()
    return l.endswith(('.wsdl', '.wsdl.xml')) or fn == 'body' or 'wsdl' in l and l.endswith('.xml')


def main():
    root, out = sys.argv[1], sys.argv[2]
    recs = []
    for dp, dn, fn in os.walk(root):
        if '.git' in dn:
            dn.remove('.git')
        for n in fn:
            if not is_candidate(n):
                continue
            p = os.path.join(dp, n)
            try:
                r = classify(p)
            except Exception as e:
                r = {'kind': 'error', 'features': [], 'size': os.path.getsize(p), 'error': repr(e)[:160]}
            r['path'] = os.path.relpath(p, root)
            r['sha256'] = hashlib.sha256(open(p, 'rb').read()).hexdigest()
            recs.append(r)
    json.dump(recs, open(out, 'w'), indent=0)
    print(len(recs), 'files')


main()
