"""Measure the captured reports and rewrite them into the proposed structure.

For each raw/<name>.nt this prints triple counts and N-Triples sizes for two
forms. It writes the as-is form as Turtle to reports/<name>.ttl and the
proposed form to dry-reports/<name>.ttl:

  as-is     the report as GraphDB returned it
  proposed  rsx:dataGraph / rsx:shapesGraph lifted from the results to the
            report (each capture has one data/shapes graph pair)

Byte counts use rdflib's N-Triples for both forms, so they are comparable.

Requires rdflib (pip install rdflib).
"""
import sys
from collections import Counter
from rdflib import Graph, Namespace, RDF

SH = Namespace("http://www.w3.org/ns/shacl#")
RSX = Namespace("http://rdf4j.org/shacl-extensions#")
LINK_PROPS = (RSX.dataGraph, RSX.shapesGraph)


def nt_size(g: Graph) -> int:
    """Bytes of the graph as N-Triples (rdflib's short blank-node labels)."""
    return len(g.serialize(format="nt", encoding="utf-8"))


def propose(g: Graph) -> Graph:
    """Move rsx:dataGraph and rsx:shapesGraph from every result to the report."""
    g = Graph() + g
    report = g.value(predicate=RDF.type, object=SH.ValidationReport)
    for r in list(g.objects(report, SH.result)):
        for p in LINK_PROPS:
            for o in list(g.objects(r, p)):
                g.remove((r, p, o))
                g.add((report, p, o))
    return g


def stats(g: Graph) -> dict:
    report = g.value(predicate=RDF.type, object=SH.ValidationReport)
    results = list(g.objects(report, SH.result))
    per_result = Counter(len(list(g.triples((r, None, None)))) for r in results)
    return {
        "results": len(results),
        "triples": len(g),
        "per_result": dict(sorted(per_result.items())),
        "rsx_triples": sum(1 for p in LINK_PROPS for _ in g.triples((None, p, None))),
        "bytes": nt_size(g),
    }


def main(names):
    rows = [["capture", "form", "results", "triples", "triples per result", "rsx triples", "N-Triples bytes"]]
    for name in names:
        g = Graph().parse(f"raw/{name}.nt", format="nt")
        for form, h, target in (("as-is", g, f"reports/{name}.ttl"), ("proposed", propose(g), f"dry-reports/{name}.ttl")):
            h.bind("sh", SH); h.bind("rsx", RSX); h.bind("rdf4j", "http://rdf4j.org/schema/rdf4j#"); h.bind("ex", "http://example.org/")
            h.serialize(target, format="turtle")
            s = stats(h)
            pr = ", ".join(f"{k}" + (f" (x{v})" if len(s["per_result"]) > 1 else "") for k, v in s["per_result"].items())
            rows.append([name, form, s["results"], s["triples"], pr, s["rsx_triples"], s["bytes"]])
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
    main(sys.argv[1:] or ["simple", "repeat", "fanout", "logic"])
