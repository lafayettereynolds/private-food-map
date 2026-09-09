"""Local SQLite VM-work proxy, not Cloudflare billed rows_read.

Reads only an explicitly supplied synthetic benchmark fixture, never remote D1.
VM instructions include joins, sort and CTE work; do not relabel them rows read.
"""
import json, pathlib, sqlite3, sys
root = pathlib.Path(sys.argv[1]).resolve()
db = sqlite3.connect('file:' + str(root / 'fixture.sqlite') + '?mode=ro&immutable=1', uri=True)
results = json.loads((root / 'benchmark.json').read_text())
for mode in results:
    total = 0
    for query in mode['queries']:
        if not query['plan']:
            continue
        steps = [0]
        def progress():
            steps[0] += 1
            return 0
        db.set_progress_handler(progress, 1)
        db.execute(query['sql'], query['values']).fetchall()
        db.set_progress_handler(None, 0)
        query['sqliteVMInstructions'] = steps[0]
        total += steps[0]
    mode['sqliteVMInstructions'] = total
(root / 'local-cost.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))
print(json.dumps([{k: r[k] for k in ('mode','sqlCount','latencyMs','sqliteVMInstructions')} for r in results]))
