#!/usr/bin/env python3
"""Compute ground truth for each WSDL: ops per binding, input wrapper element, closure over wsdl:import.
usage: expected.py corpus classified.json expected.json"""
import json, os, sys
import xml.etree.ElementTree as ET

W = 'http://schemas.xmlsoap.org/wsdl/'
S11 = 'http://schemas.xmlsoap.org/wsdl/soap/'
S12 = 'http://schemas.xmlsoap.org/wsdl/soap12/'


def q(t, ns=W):
    return '{%s}%s' % (ns, t)


def load(path, seen):
    path = os.path.normpath(path)
    if path in seen or not os.path.exists(path):
        return []
    seen.add(path)
    try:
        root = ET.parse(path).getroot()
    except Exception:
        return []
    docs = [root]
    for i in root.findall(q('import')):
        l = i.get('location')
        if l and not l.startswith('http'):
            docs += load(os.path.join(os.path.dirname(path), l.split('?')[0]), seen)
    return docs


def facts(path):
    direct = load(path, set())
    if not direct:
        return None
    root = direct[0]
    msgs, pts, ops12, ops11 = {}, {}, set(), set()
    style = {}
    for d in direct:
        for m in d.findall(q('message')):
            msgs[m.get('name')] = m.findall(q('part'))
        for pt in d.findall(q('portType')):
            for op in pt.findall(q('operation')):
                inp = op.find(q('input'))
                pts.setdefault(op.get('name'), (inp.get('message') or '').split(':')[-1] if inp is not None else None)
        for b in d.findall(q('binding')):
            ns = None
            bs = None
            for c in b:
                if c.tag == q('binding', S11):
                    ns, bs = S11, c.get('style') or 'document'
                if c.tag == q('binding', S12):
                    ns, bs = S12, c.get('style') or 'document'
            if not ns:
                continue
            for o in b.findall(q('operation')):
                (ops11 if ns == S11 else ops12).add(o.get('name'))
                so = o.find(q('operation', ns))
                style[o.get('name')] = (so.get('style') if so is not None else None) or bs
    wrappers = {}
    for name in ops11 | ops12:
        ps = msgs.get(pts.get(name)) or []
        if style.get(name) == 'rpc':
            wrappers[name] = {'style': 'rpc', 'expect': name}
        elif len(ps) == 1 and ps[0].get('element'):
            wrappers[name] = {'style': 'document', 'expect': ps[0].get('element').split(':')[-1]}
    own_ops = set()
    for b in root.findall(q('binding')):
        for o in b.findall(q('operation')):
            own_ops.add(o.get('name'))
    return {'ops11': sorted(ops11), 'ops12': sorted(ops12), 'own_ops': len(own_ops), 'wrappers': wrappers, 'closure_docs': len(direct)}


corpus, classified, out = sys.argv[1:4]
R = json.load(open(classified))
seen = set()
res = []
for r in R:
    if r['kind'] != 'wsdl11' or r['sha256'] in seen:
        continue
    seen.add(r['sha256'])
    fx = facts(os.path.join(corpus, r['path']))
    if fx is None:
        continue
    fx.update(path=r['path'], features=r['features'])
    res.append(fx)
json.dump(res, open(out, 'w'))
print(len(res), 'wsdls with facts')
