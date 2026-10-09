# Restructuring (DRY-ing) RDF4J SHACL validation reports

This folder proposes a leaner structure for the SHACL validation report that GraphDB returns when a transaction fails validation. Every claim below comes from reports captured on GraphDB **12.0.0-SHACL-SIEMENS-RC1** (RDF4J 5.3.1-jakarta-Shacl-Improvements-TR1, see `raw/graphdb-version.json`), using `rsx:DataAndShapesGraphLink` links, with synthetic data that we provide.

## Summary

- Every `sh:ValidationResult` repeats `rsx:dataGraph` for each data graph of the link and `rsx:shapesGraph` for each shapes graph.
- In our illustration, which is similar to a real-life case for a client that we have, lifting the graph pair to the report makes that report about seven times smaller, in both triple count and bytes, with no loss of information.
- As a side note, the report also includes a partial description of each failed shape, which is not needed for shapes that have an IRI.

## Problem

The following snippet illustrates the problem (from `reports/repeat.ttl`; for readability, `/` in prefixed names is not escaped here and in the examples below, so `ex:data/repeat-1` stands for `ex:data\/repeat-1`):

```turtle
[] a sh:ValidationReport ;
    sh:conforms false ;
    sh:result [ a sh:ValidationResult ;
            rsx:dataGraph ex:data/repeat-1, ex:data/repeat-2, ex:data/repeat-3,
                          ex:data/repeat-4, ex:data/repeat-5 ;
            rsx:shapesGraph ex:shapes/repeat ;
            sh:focusNode ex:sensor1 ; sh:value -1.5 ; sh:resultPath ex:reading ;
            sh:resultSeverity sh:Violation ;
            sh:sourceConstraintComponent sh:MinInclusiveConstraintComponent ;
            sh:sourceShape ex:SensorReadingShape ],
        [ a sh:ValidationResult ;
            rsx:dataGraph ex:data/repeat-1, ex:data/repeat-2, ex:data/repeat-3,
                          ex:data/repeat-4, ex:data/repeat-5 ;
            rsx:shapesGraph ex:shapes/repeat ;
            sh:focusNode ex:sensor5 ; sh:value -5.5 ; sh:resultPath ex:reading ;
            sh:resultSeverity sh:Violation ;
            sh:sourceConstraintComponent sh:MinInclusiveConstraintComponent ;
            sh:sourceShape ex:SensorReadingShape ],
        [ a sh:ValidationResult ;
            rsx:dataGraph ex:data/repeat-1, ex:data/repeat-2, ex:data/repeat-3,
                          ex:data/repeat-4, ex:data/repeat-5 ;
            rsx:shapesGraph ex:shapes/repeat ;
            sh:focusNode ex:sensor9 ; sh:value -9.5 ; sh:resultPath ex:reading ;
            sh:resultSeverity sh:Violation ;
            sh:sourceConstraintComponent sh:MinInclusiveConstraintComponent ;
            sh:sourceShape ex:SensorReadingShape ] .
```

Each result names every data graph of the link and the shapes graph again, although they are the same for all results. The report therefore grows with the number of graphs times the number of results: here, with 368 data graphs, every result is about 377 triples long instead of about eight.

## Proposal

If all results come from one data/shapes graph pair, which is the usual case of one link, `rsx:dataGraph` and `rsx:shapesGraph` go on the `sh:ValidationReport` and nowhere else. The same three results with the proposed structure:

```turtle
[] a sh:ValidationReport ;
    sh:conforms false ;
    rsx:dataGraph ex:data/repeat-1, ex:data/repeat-2, ex:data/repeat-3,
                  ex:data/repeat-4, ex:data/repeat-5 ;
    rsx:shapesGraph ex:shapes/repeat ;
    sh:result [ a sh:ValidationResult ;
            sh:focusNode ex:sensor1 ; sh:value -1.5 ; sh:resultPath ex:reading ;
            sh:resultSeverity sh:Violation ;
            sh:sourceConstraintComponent sh:MinInclusiveConstraintComponent ;
            sh:sourceShape ex:SensorReadingShape ],
        [ a sh:ValidationResult ;
            sh:focusNode ex:sensor5 ; sh:value -5.5 ; sh:resultPath ex:reading ;
            sh:resultSeverity sh:Violation ;
            sh:sourceConstraintComponent sh:MinInclusiveConstraintComponent ;
            sh:sourceShape ex:SensorReadingShape ],
        [ a sh:ValidationResult ;
            sh:focusNode ex:sensor9 ; sh:value -9.5 ; sh:resultPath ex:reading ;
            sh:resultSeverity sh:Violation ;
            sh:sourceConstraintComponent sh:MinInclusiveConstraintComponent ;
            sh:sourceShape ex:SensorReadingShape ] .
```

The cost per result drops from one triple per graph to zero—we only express the data and shapes graphs information once at root level.

## Results

| Scenario | What it shows | As is | Proposed | Factor |
|---|---|--:|--:|--:|
| `simple` | One result in a link with one data graph: nothing to lift | 15 | 15 | 1.0× |
| `repeat` | One shape violated 10 times in a link with 5 data graphs | 159 | 105 | 1.5× |
| `fanout` | One shape violated 100 times in a link with 50 data graphs | 5 906 | 857 | 6.9× |
| `logic` | Four results in a link with one data graph (also the `sh:xone` side finding) | 81 | 75 | 1.1× |

The number columns are triple counts of the whole report, as GraphDB returns it and with the proposed structure. The factor is the as-is count divided by the proposed count, so higher is better. The factor grows with both the number of data graphs in the link and the number of results, as `fanout` shows; with one data graph and one result, as in `simple`, there is nothing to gain. Byte sizes shrink in the same proportion; see `measurements.md`.

## Compatibility with the W3C report vocabulary

- SHACL requires exactly one `sh:ValidationReport` and allows additional information in the report graph. The proposal keeps one report and only moves `rsx:` properties, which are an RDF4J extension in the first place.
- Clients that read `rsx:dataGraph` from a result must follow one more step: `?result ^sh:result/rsx:dataGraph ?g`. A configuration flag could keep the old form for a transition period.
- All `sh:` properties of the results stay as they are.

## Side findings

- The report includes a partial description of each shape that results point at, once per report, with only the constraints that failed. In `repeat`, the copy of `ex:SensorReadingShape` lacks the stored shape's `sh:datatype` and `sh:maxCount`. For IRI shapes the copy is unnecessary, because `sh:sourceShape` already points at the stored shape. A blank-node shape gets a fresh label in the report and cannot be pointed to, so modellers should give IRIs to shapes whose results matter.
- `sh:xone` is silently ignored. `ex:badColour2` ("blue") matches neither member of `sh:xone` and gets no result, and the copied `ex:ItemColourShape` has no `sh:xone`. RDF4J does not list `sh:xone` among supported predicates; an error at shape load time would be better.
- A recursive shape is rejected with "Recursive shape definition detected while computing hashCode" (`raw/recursive.nt`).

## Methods

`capture.sh` loads each scenario in `input/`, then posts the link in `links/` into `rdf4j:SHACLShapeGraph`. The commit fails and the response body is the report, saved to `raw/<name>.nt`. `measure.py` counts it, writes it as pretty Turtle to `reports/<name>.ttl`, and writes the proposed form to `dry-reports/<name>.ttl`. Full table, including byte sizes: `measurements.md`. `recursive` produces an error message instead of a report and is not measured.

Raw byte counts vary by a few bytes between runs because GraphDB's blank-node labels differ in length; triple counts do not. Without an `Accept` header the report comes as `application/shacl-validation-report+n-quads;charset=ISO-8859-1` (`raw/simple-default.*`).

### Reproduce

Each scenario is independent. It needs only its own `input/<case>.trig` and `links/<case>.ttl`, uses its own graphs, classes and focus nodes, and gives the same report on an empty repository as in a repository where all other scenarios are already loaded. Every link commit fails validation and is rolled back, so nothing is left in `rdf4j:SHACLShapeGraph` afterwards (`capture.sh` prints the count after each case). Both ways were checked: every case alone in a fresh repository, and all cases in sequence in one repository; `compare.py` found the raw reports identical up to blank-node labels.

```bash
export GDB_URL=http://localhost:7200 GDB_PASSWORD=…   # GDB_USER defaults to admin
./capture.sh                       # all cases in one temporary repository, into raw/
./capture.sh repeat fanout         # only some cases
OUT=/tmp/iso ./capture.sh --isolated && python compare.py raw /tmp/iso   # one fresh repository per case
pip install rdflib && python measure.py > measurements.md
python gen-fanout.py               # regenerates input/fanout.trig and links/fanout.ttl
```

`capture.sh` creates `tmp-shacl-report-structure-<date>[-<case>]` and deletes it at the end. To run one case by hand, create a repository from `repo-config.ttl` in the Workbench, then:

```bash
CTX='context=%3Chttp%3A%2F%2Frdf4j.org%2Fschema%2Frdf4j%23SHACLShapeGraph%3E'
curl -u admin:$GDB_PASSWORD -X POST -H 'Content-Type: application/trig' \
    --data-binary @input/logic.trig $GDB_URL/repositories/REPO/statements
curl -u admin:$GDB_PASSWORD -X POST -H 'Content-Type: text/turtle' -H 'Accept: application/n-triples' \
    --data-binary @links/logic.ttl "$GDB_URL/repositories/REPO/statements?$CTX"   # HTTP 500, body = report
```

### Files

- `repo-config.ttl`: repository config; every scenario's shapes graph is on `shacl:shapesGraph`.
- `input/<case>.trig`: shapes and data per scenario; `links/<case>.ttl`: the link that triggers validation.
- `raw/`: reports exactly as GraphDB returned them (N-Triples), the GraphDB version, and the report without an `Accept` header plus its content type.
- `reports/<case>.ttl`: the raw report as formatted Turtle.
- `dry-reports/<case>.ttl`: the same report rewritten into the proposed structure by `measure.py`.
- `capture.sh`, `compare.py`, `measure.py`, `gen-fanout.py`, `measurements.md`.
