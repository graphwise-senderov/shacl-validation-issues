"""Compare the raw reports in two directories, ignoring blank-node labels.

    python compare.py DIR_A DIR_B

Reports are compared as RDF graphs (isomorphism); files that are not
N-Triples reports (recursive.nt, the default-format extras) are compared as text.
"""
import sys
from pathlib import Path
from rdflib import Graph
from rdflib.compare import isomorphic

a, b = map(Path, sys.argv[1:3])
ok = True
for fa in sorted(a.iterdir()):
    if fa.name.startswith(".") or fa.name == "graphdb-version.json":
        continue
    fb = b / fa.name
    try:
        same = isomorphic(Graph().parse(fa, format="nt"), Graph().parse(fb, format="nt"))
    except Exception:
        same = fa.read_text() == fb.read_text()
    print(f"{fa.name}: {'same' if same else 'DIFFERENT'}")
    ok &= same
sys.exit(0 if ok else 1)
