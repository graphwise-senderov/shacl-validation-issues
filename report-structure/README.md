# Restructuring (DRY-ing) RDF4J SHACL validation reports

This folder proposes a leaner structure for the SHACL validation report that GraphDB returns when a transaction fails validation. Every claim below comes from reports captured on GraphDB **12.0.0-SHACL-SIEMENS-RC1** (RDF4J 5.3.1-jakarta-Shacl-Improvements-TR1, see `raw/graphdb-version.json`), using `rsx:DataAndShapesGraphLink` links, with synthetic data that we provide.

## Summary

- Every `sh:ValidationResult` repeats `rsx:dataGraph` for each data graph of the link and `rsx:shapesGraph` for each shapes graph.
- In our illustration, which is similar to a real-life case for a client that we have, lifting the graph pair to the report makes that report about seven times smaller, in both triple count and bytes, with no loss of information.
- The report also includes a partial description of each failed shape. That isn't needed, because every result already references its shape with `sh:sourceShape`, and the shape is in the database. The exception is blank-node shapes, which can't be referenced from outside their graph; we suggest how to fix that below.

## Problem

### Every result repeats the graph pair

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

### Every validation response report includes the failed shapes

Besides the results, the validation response report contains a partial description of each shape that results point at:

```turtle
[] a sh:ValidationReport ;
    sh:result [ a sh:ValidationResult ; … ; sh:sourceShape ex:SensorReadingShape ],
        … .   # ten results, all with the same sh:sourceShape

# stored, in ex:shapes/repeat, but also copied in the report
ex:SensorReadingShape a sh:PropertyShape ;
    sh:path ex:reading ;
    sh:minInclusive 0.0 ;
    sh:name "reading" ; sh:description "A non-negative decimal reading." ;
    sh:message "Reading must be a non-negative decimal." .
```

Those triples are not needed, because the shape can be retrieved from the database via the `sh:sourceShape` value of each `sh:ValidationResult`.  However, a blank-node shape gets a fresh label in the report, so it cannot be traced back to the stored shape.

### Proposal

#### Level 1: the graph pair goes on the report

If all results come from one data/shapes graph pair, which is the usual case of one link, `rsx:dataGraph` and `rsx:shapesGraph` go on the `sh:ValidationReport` and nowhere else. The same three results after level 1:

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

The cost per result drops from one triple per graph to zero. A transaction with several links, and so several data/shapes graph pairs, is left to the implementers, who may group the results differently or reject it.

#### Level 2: shapes are referenced, not copied

An IRI shape is not copied. `sh:sourceShape ex:SensorReadingShape` resolves in the shapes graph that the report names, so the level 1 example above is already the level 2 form for `repeat`. An option to include full copies keeps the report self-contained for consumers that need it.

A blank-node shape cannot be referenced from outside its graph, so its description stays in the report, once and completely, as GraphDB already does for the blank e-mail property shape of `bnode`. It also needs a stable way to be found again in the shapes graph (see the recommended scheme below).

```turtle
[] a sh:ValidationReport ;
    sh:result [ a sh:ValidationResult ; sh:focusNode ex:c2 ; sh:sourceShape _:email ; … ],
              [ a sh:ValidationResult ; sh:focusNode ex:c3 ; sh:sourceShape _:email ; … ] .
_:email a sh:PropertyShape ; sh:path ex:email ; sh:pattern "^[^@]+@[^@]+$" ; sh:maxCount 1 .
```

## Results

| Scenario | What it shows | As is | Level 1 | Level 2 | Factor |
|---|---|--:|--:|--:|--:|
| `simple` | One missing value; the copied shape is partial | 15 | 15 | 12 | 1.3× |
| `repeat` | One shape violated 10 times in a link with 5 data graphs | 159 | 105 | 99 | 1.6× |
| `fanout` | One shape violated 100 times in a link with 50 data graphs | 5 906 | 857 | 854 | 6.9× |
| `logic` | Violations inside `sh:or`, `sh:and` and `sh:not` | 81 | 75 | 37 | 2.2× |
| `bnode` | Six results on blank-node property shapes | 66 | 56 | 56 | 1.2× |
| `node` | A violation through `sh:node` | 22 | 22 | 16 | 1.4× |

The three number columns are triple counts of the whole report: as GraphDB returns it, after level 1, and after level 2. The factor is the as-is count divided by the level 2 count, so higher is better. Level 1 matters most when a link has many data graphs and many results, as in `fanout`; the factor grows with both. Level 2 saves a fixed amount per report, which is large when nested shapes are copied, as in `logic`, and zero for blank-node shapes, as in `bnode`. Byte sizes shrink in the same proportion; see `measurements.md`.

## Logical constraints, blank nodes and `sh:node`

What the captures show (`reports/*.ttl`):

| Case                                                          | `sh:sourceShape`                          | Component                                 | What is missing                                    |
|---------------------------------------------------------------|-------------------------------------------|-------------------------------------------|----------------------------------------------------|
| `sh:or ( [datatype string] [datatype integer] )`              | outer property shape                      | `sh:OrConstraintComponent`                | nothing for `or`: all members failed by definition |
| `sh:and ( [minLength 2] [maxLength 5] )`                      | outer property shape                      | `sh:AndConstraintComponent`               | which member failed (here `maxLength`)             |
| `sh:not [hasValue "none"]`                                    | outer property shape                      | `sh:NotConstraintComponent`               | nothing: the inner shape conformed                 |
| `sh:xone ( … )`                                               | no result at all                          |                                           | see side findings                                  |
| `sh:node ex:AddressShape`                                     | outer blank property shape                | `sh:NodeConstraintComponent`              | the nested postcode failure                        |
| blank `sh:property [ … ]`                                     | the blank node, shared by all its results | as failed                                 | a link to the stored node                          |

Pointing at the outer shape is correct. SHACL defines `sh:sourceShape` as the shape the focus node was validated against, and the constraint component belongs to that shape. The member that caused the failure is additional information, and SHACL already has a place for it: `sh:detail`, which the spec mentions explicitly for `sh:node`.

The hard part is naming a member without copying it. A member of an `sh:or` / `sh:and` / `sh:xone` list is just the node in `rdf:first`; a result can reference that node directly, with no need to copy the list. The problem is only that the node is usually blank. Three ways to address a blank shape, and their limits:

1.  **Parent and list index**, e.g. `ex:ItemSizeShape`, `sh:and`, member 2. Works for lists and for `sh:not`, but not for `sh:property`, whose values have no order, and two property shapes on the same path are common. The index changes when the list is edited. A nested member needs a chain of steps back to the nearest IRI.
2.  **Content hash**, a deterministic IRI computed from the canonical triples of the shape. Stable across reloads and works everywhere. Two identical blank shapes under different parents get the same id, and any edit gives a new id. GraphDB already hashes shapes internally (see the recursive shape under side findings).
3.  **IRIs in the shapes graph.** The only fully reliable way, and the one to recommend to modellers for shapes whose results matter.

### Recommended scheme

- `sh:sourceShape` stays the shape that owns the failing constraint component, as today.
- IRI shapes are referenced, not copied (level 2).
- A blank source shape is described once and completely. To be found again in the shapes graph, it needs a stable identifier, such as a content hash or its parent shape plus position, as described above. Which vocabulary carries that identifier is left to the implementers; giving the shape an IRI avoids the problem.
- When asked for, a result for `sh:and`, `sh:or` or `sh:node` gets `sh:detail` child results whose `sh:sourceShape` is the failing member, addressed the same way. For `sh:not` there is nothing to detail. This is optional because it makes reports larger.

```turtle
# proposed: an sh:and result that names the failing member
_:r sh:sourceShape ex:ItemSizeShape ; sh:sourceConstraintComponent sh:AndConstraintComponent ;
    sh:detail [ a sh:ValidationResult ; sh:focusNode ex:badSize ; sh:sourceShape _:m2 ;
                sh:sourceConstraintComponent sh:MaxLengthConstraintComponent ] .
_:m2 sh:maxLength 5 .   # the second member of the sh:and list
```

Limits: a blank shape used by two parents has two addresses but one id; `sh:property` members can only be found by id or by content; and recursive shapes, which references would handle without infinite copying, are rejected by GraphDB today.

## Compatibility with the W3C report vocabulary

- SHACL requires exactly one `sh:ValidationReport` and allows additional information in the report graph. Level 1 keeps one report and only moves `rsx:` properties, which are an RDF4J extension in the first place.
- Clients that read `rsx:dataGraph` from a result must follow one more step: `?result ^sh:result/rsx:dataGraph ?g`. A configuration flag could keep the old form for a transition period.
- `sh:sourceShape`, `sh:sourceConstraintComponent` and `sh:detail` are used as the spec defines them. Keeping a blank-node copy as the value of `sh:sourceShape`, rather than replacing it by a hash IRI, means that no standard consumer loses information.

## Side findings

- `sh:xone` is silently ignored. `ex:badColour2` ("blue") matches neither member of `sh:xone` and gets no result, and the copied `ex:ItemColourShape` has no `sh:xone`. RDF4J does not list `sh:xone` among supported predicates; an error at shape load time would be better.
- A recursive shape is rejected with "Recursive shape definition detected while computing hashCode" (`raw/recursive.nt`).

## Methods

`capture.sh` loads each scenario in `input/`, then posts the link in `links/` into `rdf4j:SHACLShapeGraph`. The commit fails and the response body is the report, saved to `raw/<name>.nt`. `measure.py` counts it, writes it as pretty Turtle to `reports/<name>.ttl`, and writes the two proposed forms to `dry-reports/`. Full table, including byte sizes: `measurements.md`. `recursive` produces an error message instead of a report and is not measured.

Raw byte counts vary by a few bytes between runs because GraphDB's blank-node labels differ in length; triple counts do not. Without an `Accept` header the report comes as `application/shacl-validation-report+n-quads;charset=ISO-8859-1` (`raw/simple-default.*`).

### Reproduce

Each scenario is independent. It needs only its own `input/<case>.trig` and `links/<case>.ttl`, uses its own graphs, classes and focus nodes, and gives the same report on an empty repository as in a repository where all other scenarios are already loaded. Every link commit fails validation and is rolled back, so nothing is left in `rdf4j:SHACLShapeGraph` afterwards (`capture.sh` prints the count after each case). Both ways were checked: every case alone in a fresh repository, and all cases in sequence in one repository; `compare.py` found the raw reports identical up to blank-node labels.

```bash
export GDB_URL=http://localhost:7200 GDB_PASSWORD=…   # GDB_USER defaults to admin
./capture.sh                       # all cases in one temporary repository, into raw/
./capture.sh logic bnode           # only some cases
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
- `dry-reports/<case>-level1.ttl`, `-level2.ttl`: the same report rewritten into the two proposed forms by `measure.py`.
- `capture.sh`, `compare.py`, `measure.py`, `gen-fanout.py`, `measurements.md`.
