"""Measure the captured reports and rewrite them into the proposed structure.

For each raw/<name>.nt this prints triple counts and N-Triples sizes for
three forms. It writes the as-is form as Turtle to reports/<name>.ttl and the
two proposed forms to dry-reports/<name>-level1.ttl and -level2.ttl:

  as-is   the report as GraphDB returned it
  level1  rsx:dataGraph / rsx:shapesGraph lifted from the results to the report
          (or to one rsx:GraphPair node per distinct pair, if there are several)
  level2  level1, with copied shape triples kept only for blank-node source shapes;
          an IRI shape is referenced by sh:sourceShape <iri> and resolves in the
          shapes graph named on the report

Byte counts use rdflib's N-Triples for all three forms, so they are comparable.

Requires rdflib (pip install rdflib).
"""
import sys
from collections import Counter
from pathlib import Path
from rdflib import BNode, Graph, Namespace, RDF, URIRef

SH = Namespace("http://www.w3.org/ns/shacl#")
RSX = Namespace("http://rdf4j.org/shacl-extensions#")
LINK_PROPS = (RSX.dataGraph, RSX.shapesGraph)


def nt_size(g: Graph) -> int:
    """Bytes of the graph as N-Triples (rdflib's short blank-node labels)."""
    return len(g.serialize(format="nt", encoding="utf-8"))


def level1(g: Graph) -> Graph:
    g = Graph() + g
    report = g.value(predicate=RDF.type, object=SH.ValidationReport)
    pairs = {}
    for r in g.objects(report, SH.result):
        key = tuple(tuple(sorted(g.objects(r, p))) for p in LINK_PROPS)
        pairs.setdefault(key, []).append(r)
        for p in LINK_PROPS:
            g.remove((r, p, None))
    for (data, shapes), results in pairs.items():
        node = report
        if len(pairs) > 1:
            node = BNode()
            g.add((node, RDF.type, RSX.GraphPair))
            g.add((report, RSX.graphPair, node))
            for r in results:
                g.add((r, RSX.graphPair, node))
        for d in data:
            g.add((node, RSX.dataGraph, d))
        for s in shapes:
            g.add((node, RSX.shapesGraph, s))
    return g


def closure(g: Graph, node) -> set:
    """Triples of node plus those of blank nodes reachable from it."""
    seen, todo, out = set(), [node], set()
    while todo:
        n = todo.pop()
        if n in seen:
            continue
        seen.add(n)
        for t in g.triples((n, None, None)):
            out.add(t)
            if isinstance(t[2], BNode):
                todo.append(t[2])
    return out


def level2(g: Graph) -> Graph:
    """Keep the report, its results, and copies of blank-node source shapes only."""
    report = g.value(predicate=RDF.type, object=SH.ValidationReport)
    keep = closure(g, report)
    for shape in set(g.objects(None, SH.sourceShape)):
        if isinstance(shape, BNode):
            keep |= closure(g, shape)
    h = Graph()
    for t in keep:
        h.add(t)
    return h


def stats(g: Graph) -> dict:
    report = g.value(predicate=RDF.type, object=SH.ValidationReport)
    results = list(g.objects(report, SH.result))
    own = sum(1 for n in [report, *results] for _ in g.triples((n, None, None)))
    per_result = Counter(len(list(g.triples((r, None, None)))) for r in results)
    return {
        "results": len(results),
        "triples": len(g),
        "per_result": dict(sorted(per_result.items())),
        "rsx_triples": sum(1 for p in LINK_PROPS for _ in g.triples((None, p, None))),
        "other_triples": len(g) - own,
        "bytes": nt_size(g),
    }


def main(names):
    for d in ("reports", "dry-reports"):
        Path(d).mkdir(exist_ok=True)
    rows = [["capture", "form", "results", "triples", "triples per result", "rsx triples", "shape and pair triples", "N-Triples bytes"]]
    for name in names:
        g = Graph().parse(f"raw/{name}.nt", format="nt")
        raw = Path(f"raw/{name}.nt").read_text().splitlines()
        dup = len(raw) - len(set(raw))
        for form, h in (("as-is", g), ("level1", level1(g)), ("level2", level2(level1(g)))):
            h.bind("sh", SH); h.bind("rsx", RSX); h.bind("rdf4j", "http://rdf4j.org/schema/rdf4j#"); h.bind("ex", "http://example.org/")
            target = f"reports/{name}.ttl" if form == "as-is" else f"dry-reports/{name}-{form}.ttl"
            h.serialize(target, format="turtle")
            s = stats(h)
            pr = ", ".join(f"{k}" + (f" (x{v})" if len(s['per_result']) > 1 else "") for k, v in s["per_result"].items())
            rows.append([name, form, s["results"], s["triples"], pr, s["rsx_triples"], s["other_triples"], s["bytes"]])
        if dup:
            rows.append([name, f"(raw file has {dup} duplicate lines)", "", "", "", "", "", ""])
    print_table(rows)


def print_table(rows):
    """Print a Markdown table with padded columns; text columns left, numbers right."""
    rows = [[str(c) for c in r] for r in rows]
    widths = [max(len(r[i]) for r in rows) for i in range(len(rows[0]))]
    fmt = lambda r: "| " + " | ".join(c.ljust(w) if i < 2 else c.rjust(w) for i, (c, w) in enumerate(zip(r, widths))) + " |"
    print(fmt(rows[0]))
    print("|" + "|".join("-" * (w + 2) if i < 2 else "-" * (w + 1) + ":" for i, w in enumerate(widths)) + "|")
    for r in rows[1:]:
        print(fmt(r))


if __name__ == "__main__":
    main(sys.argv[1:] or ["simple", "repeat", "fanout", "logic", "bnode", "node", "twolinks"])
