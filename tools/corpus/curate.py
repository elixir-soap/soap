#!/usr/bin/env python3
"""Select a curated corpus by greedy feature cover. usage: curate.py SCRATCH OUT_DIR [--write]"""
import json, os, re, shutil, subprocess, sys, collections
import xml.etree.ElementTree as ET

SP, OUT = sys.argv[1], sys.argv[2]
WRITE = '--write' in sys.argv
CORPUS = os.path.join(SP, 'corpus')
PERMISSIVE = {
    'vpulim__node-soap': 'MIT', 'savonrb__wasabi': 'MIT', 'savonrb__savon': 'MIT', 'php__php-src': 'BSD-3-Clause',
    'bet365__soap': 'Apache-2.0', 'apache__cxf': 'Apache-2.0', 'apache__axis-axis2-java-core': 'Apache-2.0',
    'phpro__soap-client': 'MIT', 'php-soap__wsdl': 'MIT', 'wsdl2phpgenerator__wsdl2phpgenerator': 'MIT', 'dotnet__wcf': 'MIT',
    'mvantellingen__python-zeep': 'MIT',
}
PREF = ['vpulim__node-soap', 'mvantellingen__python-zeep', 'php__php-src', 'savonrb__wasabi', 'php-soap__wsdl', 'dotnet__wcf', 'bet365__soap', 'wsdl2phpgenerator__wsdl2phpgenerator', 'phpro__soap-client', 'savonrb__savon', 'apache__axis-axis2-java-core', 'apache__cxf']
SKIP_FEATURE_PREFIX = ('size:', 'doc:')
XSD = '{http://www.w3.org/2001/XMLSchema}'
WSDL = '{http://schemas.xmlsoap.org/wsdl/}'

R = json.load(open(os.path.join(SP, 'classified.json')))
base = {}
for l in open(os.path.join(SP, 'baseline.jsonl')):
    r = json.loads(l)
    base[r['path']] = r


def src(p):
    s = p.split('/')
    return s[1] if s[0] == 'oss' else 'live'


def closure(path):
    """relative dependency closure; returns (files, missing, remote)"""
    files, missing, remote = [], [], []
    todo, seen = [path], set()
    while todo:
        p = os.path.normpath(todo.pop())
        if p in seen:
            continue
        seen.add(p)
        if not os.path.exists(p):
            missing.append(p)
            continue
        files.append(p)
        try:
            root = ET.parse(p).getroot()
        except Exception:
            continue
        for el in root.iter():
            if el.tag == WSDL + 'import':
                loc = el.get('location')
            elif el.tag in (XSD + 'import', XSD + 'include', XSD + 'redefine'):
                loc = el.get('schemaLocation')
            else:
                continue
            if not loc:
                continue
            if re.match(r'[a-z]+:', loc):
                remote.append(loc)
            else:
                todo.append(os.path.join(os.path.dirname(p), loc.split('?')[0]))
    return files, missing, remote


def derived(r):
    fs = set(r['features'])
    out = set(f for f in fs if not f.startswith(SKIP_FEATURE_PREFIX))
    vers = [v for v in ('soap11', 'soap12') if 'binding:' + v in fs]
    combos = [f.split(':', 1)[1] for f in fs if f.startswith('combo:')]
    for v in vers:
        for c in combos:
            out.add(f'x:{v}+{c}')
    for c in combos:
        for a in ('action:empty', 'action:missing'):
            if a in fs:
                out.add(f'x:{c}+{a}')
        for p in ('prefix:xsd-s', 'prefix:xsd-xs', 'prefix:xsd-default', 'prefix:wsdl-default-and-alias', 'prefix:wsdl-default', 'wrapper:element-ne-op', 'msg:multi-part', 'header:declared-input'):
            if p in fs:
                out.add(f'x:{c}+{p}')
    if 'import:wsdl' in fs and 'import:xsd-located' in fs:
        out.add('x:wsdl-import+xsd-import')
    b = base.get(r['path'])
    if b:
        if not b['default']['ok']:
            out.add('baseline:parse-crash:' + b['default']['crash'][:24])
        for x in b['bodies']:
            if x['build'] == 'crash':
                out.add('baseline:body-crash')
            elif x['build'] == 'ok' and not x['wrapper_ok']:
                out.add('baseline:wrong-wrapper')
            elif x['build'] == 'ok' and not x['wellformed']:
                out.add('baseline:malformed-body')
    return out


uniq = {}
for r in R:
    if r['kind'] in ('wsdl11', 'wsdl20'):
        uniq.setdefault(r['sha256'], r)
cands = []
for r in uniq.values():
    s = src(r['path'])
    if s == 'live' or s not in PERMISSIVE:
        continue
    files, missing, remote = closure(os.path.join(CORPUS, r['path']))
    total = sum(os.path.getsize(f) for f in files)
    r2 = dict(r, f=derived(r), files=files, missing=missing, remote=remote, total=total, s=s)
    cands.append(r2)

ALL = set().union(*(c['f'] for c in cands))
TARGET = 2
got = collections.Counter()
got_src = collections.defaultdict(set)
picked = []
remaining = cands[:]


def gain(c):
    g = 0
    for f in c['f']:
        if got[f] < TARGET and c['s'] not in got_src[f]:
            g += 2 if got[f] == 0 else 1
    return g


while True:
    best = None
    bs = 0
    for c in remaining:
        g = gain(c)
        if g == 0:
            continue
        # value per kilobyte with penalties for broken closures and non-preferred sources
        penalty = (3 if c['missing'] else 1) * (1.5 if c['remote'] else 1)
        score = g / (penalty * (1 + c['total'] / 40000) * (1 + PREF.index(c['s']) * 0.04))
        if score > bs:
            best, bs = c, score
    if not best:
        break
    picked.append(best)
    remaining.remove(best)
    for f in best['f']:
        got[f] += 1
        got_src[f].add(best['s'])

missing_cov = sorted(ALL - set(got))
total = sum(c['total'] for c in picked)
by_src = collections.Counter(c['s'] for c in picked)
print('candidates', len(cands), 'features', len(ALL), 'picked', len(picked), 'bytes', total, 'uncovered', missing_cov)
print(by_src)
single = sorted(f for f in ALL if got[f] == 1)
print('features with one example:', len(single), single)
print('picked with broken closure:', sum(1 for c in picked if c['missing']))
print('largest:', sorted(((c['total'], c['path']) for c in picked), reverse=True)[:6])

json.dump([{k: c[k] for k in ('path', 's', 'total', 'sha256')} | {'f': sorted(c['f']), 'missing': len(c['missing']), 'remote': c['remote'][:5], 'files': [os.path.relpath(x, CORPUS) for x in c['files']]} for c in picked], open(os.path.join(SP, 'picked.json'), 'w'), indent=0)
