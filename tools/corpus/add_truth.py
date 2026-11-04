#!/usr/bin/env python3
"""Add independently computed facts ("truth") to test/corpus/manifest.json.

The conformance suite compares each client against these facts, so they are
derived here with a separate XML stack instead of the code under test.

usage: add_truth.py test/corpus
"""
import io
import json
import os
import sys
import xml.etree.ElementTree as ET

W = 'http://schemas.xmlsoap.org/wsdl/'
S11 = 'http://schemas.xmlsoap.org/wsdl/soap/'
S12 = 'http://schemas.xmlsoap.org/wsdl/soap12/'


def q(t, ns=W):
    return '{%s}%s' % (ns, t)


def read_doc(path):
    raw = open(path, 'rb').read()
    prefixes = {}
    for _, (p, u) in ET.iterparse(io.BytesIO(raw), events=('start-ns',)):
        prefixes.setdefault(p, u)
    return ET.fromstring(raw), prefixes


def load(path, seen):
    path = os.path.normpath(path)
    if path in seen or not os.path.exists(path):
        return []
    seen.add(path)
    try:
        root, prefixes = read_doc(path)
    except ET.ParseError:
        return []
    docs = [(root, prefixes)]
    for imp in root.findall(q('import')):
        loc = imp.get('location')
        if loc and not loc.startswith(('http:', 'https:', 'file:')):
            docs += load(os.path.join(os.path.dirname(path), loc.split('?')[0]), seen)
    return docs


def truth(path):
    docs = load(path, set())
    if not docs or docs[0][0].tag != q('definitions'):
        return None
    messages, inputs, ops, ports = {}, {}, {}, []
    for root, prefixes in docs:
        tns = root.get('targetNamespace')
        for m in root.findall(q('message')):
            messages[m.get('name')] = (m.findall(q('part')), prefixes)
        for pt in root.findall(q('portType')):
            for op in pt.findall(q('operation')):
                i = op.find(q('input'))
                if i is not None:
                    inputs.setdefault(op.get('name'), (i.get('message') or '').split(':')[-1])
        versions = {}
        for b in root.findall(q('binding')):
            soap = next((c for c in b if c.tag in (q('binding', S11), q('binding', S12))), None)
            if soap is None:
                continue
            ns = S11 if soap.tag == q('binding', S11) else S12
            version = '1.1' if ns == S11 else '1.2'
            versions[b.get('name')] = version
            for o in b.findall(q('operation')):
                so = o.find(q('operation', ns))
                style = (so.get('style') if so is not None else None) or soap.get('style') or 'document'
                io_el = o.find(q('input'))
                body = io_el.find(q('body', ns)) if io_el is not None else None
                entry = ops.setdefault(o.get('name'), {'bindings': []})
                entry['bindings'].append({
                    'version': version,
                    'action': so.get('soapAction') if so is not None else None,
                    'style': style,
                    'use': (body.get('use') if body is not None else None) or 'literal',
                    'body_namespace': body.get('namespace') if body is not None else None,
                    'has_input': io_el is not None,
                })
        for s in root.findall(q('service')):
            for p in s.findall(q('port')):
                for a in p:
                    if a.tag in (q('address', S11), q('address', S12)):
                        ports.append({'service': s.get('name'), 'port': p.get('name'), 'location': a.get('location'), 'version': '1.1' if a.tag == q('address', S11) else '1.2'})
    for name, entry in ops.items():
        parts, prefixes = messages.get(inputs.get(name), ([], {}))
        first = entry['bindings'][0]
        wrapper = None
        if first['style'] == 'rpc' and inputs.get(name) is None and not first['has_input']:
            wrapper = None
        elif first['style'] == 'rpc':
            wrapper = {'name': name, 'namespace': first['body_namespace']}
        elif len(parts) == 1 and parts[0].get('element'):
            qn = parts[0].get('element')
            prefix, local = qn.split(':', 1) if ':' in qn else ('', qn)
            wrapper = {'name': local, 'namespace': prefixes.get(prefix)}
        entry['wrapper'] = wrapper
    return {'operations': ops, 'ports': ports}


corpus = sys.argv[1]
path = os.path.join(corpus, 'manifest.json')
manifest = json.load(open(path))
count = 0
for e in manifest['entries']:
    t = truth(os.path.join(corpus, e['local']))
    if t is not None:
        e['truth'] = t
        count += 1
json.dump(manifest, open(path, 'w'), indent=1)
print('truth added to', count, 'of', len(manifest['entries']))
