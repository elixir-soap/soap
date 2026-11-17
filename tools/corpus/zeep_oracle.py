"""Cross-check ground-truth op counts with zeep, offline. usage: zeep_oracle.py CORPUS picked.json expected.json out.json"""
import json, multiprocessing as mp, os, sys, logging
logging.disable(logging.CRITICAL)


def run(args):
    path, q = args
    import zeep
    from zeep.transports import Transport

    class Offline(Transport):
        def load(self, url):
            if url.startswith(('http:', 'https:')):
                raise IOError('offline')
            return super().load(url)

    try:
        doc = zeep.wsdl.Document(path, Offline(), settings=zeep.Settings(strict=False))
        ops = set()
        vers = set()
        styles = set()
        for b in doc.bindings.values():
            for name, op in b._operations.items():
                ops.add(name)
                styles.add(getattr(op, 'style', None))
            vers.add(type(b).__name__)
        q.put(('ok', sorted(ops), sorted(vers), sorted(str(s) for s in styles)))
    except BaseException as e:
        q.put(('error', type(e).__name__, str(e)[:120]))


def guarded(path):
    q = mp.Queue()
    p = mp.Process(target=run, args=((path, q),))
    p.start()
    p.join(30)
    if p.is_alive():
        p.kill()
        return ('error', 'timeout', '')
    return q.get() if not q.empty() else ('error', 'died', '')


if __name__ == '__main__':
    corpus, picked, expected, out = sys.argv[1:5]
    exp = {e['path']: e for e in json.load(open(expected))}
    res = []
    for p in json.load(open(picked)):
        r = guarded(os.path.join(corpus, p['path']))
        e = exp.get(p['path'], {})
        want = set(e.get('ops11', [])) | set(e.get('ops12', []))
        if r[0] == 'ok':
            got = set(r[1])
            res.append(dict(path=p['path'], zeep='ok', zeep_ops=len(got), truth_ops=len(want), agree=got == want, only_zeep=sorted(got - want)[:4], only_truth=sorted(want - got)[:4], bindings=r[2]))
        else:
            res.append(dict(path=p['path'], zeep='error', err=r[1], msg=r[2], truth_ops=len(want)))
    json.dump(res, open(out, 'w'), indent=0)
    ok = [r for r in res if r['zeep'] == 'ok']
    print('picked', len(res), 'zeep ok', len(ok), 'agree', sum(r['agree'] for r in ok))
    for r in ok:
        if not r['agree']:
            print(' DIFF', r['path'][-60:], r['truth_ops'], r['zeep_ops'], r['only_zeep'], r['only_truth'])
    import collections
    print(collections.Counter(r['err'] for r in res if r['zeep'] == 'error'))
    for r in res:
        if r['zeep'] == 'error':
            print(' ERR', r['path'][-55:], r['err'], r['msg'][:70])
