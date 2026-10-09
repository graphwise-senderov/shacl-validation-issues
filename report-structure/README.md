# Restructuring GraphDB SHACL validation reports

This folder proposes a leaner structure for the SHACL validation report that GraphDB returns when a transaction fails validation. Every claim below comes from reports captured on GraphDB **12.0.0-SHACL-SIEMENS-RC1** (RDF4J 5.3.1-jakarta-Shacl-Improvements-TR1, see `raw/graphdb-version.json`), in `rsx:DataAndShapesGraphLink` mode, with synthetic data only.

## Summary

- Every `sh:ValidationResult` repeats `rsx:dataGraph` for each data graph of the link and `rsx:shapesGraph` for each shapes graph. With 50 data graphs this is 51 of the 58 triples of each result, and 86% of the whole report.
- Lifting the graph pair to the report cuts that report from 5906 to 857 triples and from 710 KB to 104 KB (same serializer for both), with no loss of information.
- The report does copy the source shape, but **once per report, not once per result**. This holds for IRI shapes and for blank-node shapes. The copy is partial: it holds only the parameters of the constraints that failed, plus `sh:name`, `sh:description` and `sh:message`. For `sh:or`, `sh:and`, `sh:not`, `sh:node` and `sh:qualifiedValueShape` it also copies the nested shapes in full.
- For logical constraints the result points at the outer shape. Nothing in the report says which member of an `sh:and` failed, and nested `sh:node` failures are not reported.

## The problem, measured

`capture.sh` loads each scenario in `input/`, then posts the link in `links/` into `rdf4j:SHACLShapeGraph`. The commit fails and the response body is the report, saved to `raw/<name>.nt`. `measure.py` counts it, writes it as pretty Turtle to `reports/<name>.ttl`, and writes the proposed forms to `dry-reports/`. Full table: `measurements.md`.

| Scenario                             | Data graphs in link | Results | Triples | Triples per result | of which `rsx:` | Bytes (GraphDB) |
|--------------------------------------|--------------------:|--------:|--------:|-------------------:|----------------:|----------------:|
| `simple`: one missing name           |                   1 |       1 |      15 |                  8 |               2 |           1 951 |
| `repeat`: same shape, 10 violations  |                   5 |      10 |     159 |                 14 |               6 |          20 978 |
| `fanout`: same shape, 100 violations |                  50 |     100 |   5 906 |                 58 |              51 |         773 637 |

Raw byte counts vary by a few bytes between runs because GraphDB's blank-node labels differ in length; triple counts do not.

A result costs about seven triples of its own (type, focus node, path, value, severity, constraint component, source shape, and a message if the shape has one) plus `|data graphs| + |shapes graphs|`. The second term is the same for every result of a link. A link with 368 data graphs therefore makes every result about 377 triples long, which is what turns a few thousand results into a report of hundreds of megabytes.

Excerpt from `reports/repeat.ttl` (as Turtle, two of ten results; prefixed names containing `/` are shortened for reading):

```turtle
[] a sh:ValidationReport ;
    sh:conforms false ;
    sh:result [ a sh:ValidationResult ;
            rsx:dataGraph ex:data/repeat-1, ex:data/repeat-2, ex:data/repeat-3,
                          ex:data/repeat-4, ex:data/repeat-5 ;
            rsx:shapesGraph ex:shapes/repeat ;
            sh:focusNode ex:sensor1 ; sh:value -1.5 ; sh:resultPath ex:reading ;
            sh:resultMessage "Reading must be a non-negative decimal." ;
            sh:resultSeverity sh:Violation ;
            sh:sourceConstraintComponent sh:MinInclusiveConstraintComponent ;
            sh:sourceShape ex:SensorReadingShape ],
        [ a sh:ValidationResult ;
            rsx:dataGraph ex:data/repeat-1, ex:data/repeat-2, ex:data/repeat-3,
                          ex:data/repeat-4, ex:data/repeat-5 ;
            rsx:shapesGraph ex:shapes/repeat ;
            sh:focusNode ex:sensor5 ; sh:value -5.5 ; sh:resultPath ex:reading ;
            # … same five lines as above …
            sh:sourceShape ex:SensorReadingShape ] .

# Copied once, although ten results point at it. sh:datatype and sh:maxCount
# of the stored shape are missing because they did not fail.
ex:SensorReadingShape a sh:PropertyShape ; sh:path ex:reading ;
    sh:minInclusive 0.0 ; sh:name "reading" ;
    sh:description "A non-negative decimal reading." ;
    sh:message "Reading must be a non-negative decimal." .
```

## Is the whole shape repeated in every result?

We checked this claim against every capture. It does not hold in this version, but a weaker form does:

- **Copied once.** In `repeat` and `fanout`, ten and a hundred results share one copy of the IRI shape. In `bnode`, six results (two constraint components, four focus nodes) share one blank node label (`_:node18`), and its triples appear once. No capture contains a duplicate line.
- **Partial.** `simple` copies `ex:PersonNameShape` with `sh:minCount` but without `sh:datatype`. A reader of the report sees a shape that differs from the stored one.
- **Nested shapes are copied in full.** `logic` copies both members of each `sh:or` / `sh:and` list and the named shapes behind `sh:or ( ex:PersonOwnerShape ex:OrgOwnerShape )`. `node` copies `ex:AddressShape` with all its constraints, although only `sh:pattern` failed. In `logic`, 38 of 81 triples are shape copies.
- **Blank-node copies cannot be traced back.** The copied blank node gets a fresh label, so a consumer cannot find the stored shape it came from except by comparing content.

So the size problem is the graph pair, not the shapes. The shapes are a problem of clarity and traceability.

## Proposal

### Level 1: the graph pair goes on the report

If all results come from one data/shapes graph pair, which is the usual case of one link, put `rsx:dataGraph` and `rsx:shapesGraph` on the `sh:ValidationReport` and nowhere else. If one transaction validates several pairs, add one node per pair and one triple per result that points at it:

```turtle
[] a sh:ValidationReport ;
    rsx:graphPair _:p1, _:p2 ;
    sh:result [ a sh:ValidationResult ; rsx:graphPair _:p1 ; … ] .
_:p1 a rsx:GraphPair ; rsx:dataGraph ex:data/simple ; rsx:shapesGraph ex:shapes/simple .
```

The cost per result drops from `|D| + |S|` triples to zero or one. The link IRI could serve as the pair node, but shapes in `rdf4j:SHACLShapeGraph` (`plain`) have no link, so a dedicated node is simpler.

### Level 2: shapes on the report, results only reference them

- An IRI source shape is not copied. `sh:sourceShape <iri>` resolves in the shapes graph that the report already names.
- A blank-node source shape is copied once per report, as GraphDB does now, but completely and with an address that locates it in the shapes graph (see below).
- An option to include full copies of IRI shapes keeps the report self-contained for consumers that need it.

### Before and after

The same ten results of `repeat` (files `reports/repeat.ttl` and `dry-reports/repeat-level2.ttl`):

```turtle
# after: 99 triples instead of 159, 8 per result instead of 14
[] a sh:ValidationReport ;
    sh:conforms false ;
    rsx:dataGraph ex:data/repeat-1, ex:data/repeat-2, ex:data/repeat-3,
                  ex:data/repeat-4, ex:data/repeat-5 ;
    rsx:shapesGraph ex:shapes/repeat ;
    sh:result [ a sh:ValidationResult ;
            sh:focusNode ex:sensor1 ; sh:value -1.5 ; sh:resultPath ex:reading ;
            sh:resultMessage "Reading must be a non-negative decimal." ;
            sh:resultSeverity sh:Violation ;
            sh:sourceConstraintComponent sh:MinInclusiveConstraintComponent ;
            sh:sourceShape ex:SensorReadingShape ],
        … .
```

| Scenario                                          |                 As is |     Level 1 |     Level 2 |
|---------------------------------------------------|----------------------:|------------:|------------:|
| `repeat` (10 results, 5 graphs)                   |           159 triples |         105 |          99 |
| `fanout` (100 results, 50 graphs)                 | 5 906 triples, 710 KB | 857, 104 KB | 854, 104 KB |
| `logic` (4 results, 1 graph)                      |            81 triples |          75 |          37 |
| `twolinks` (3 results, 2 pairs of one graph each) |            38 triples |          43 |          40 |

Level 1 pays off as soon as a link has more than one graph and more than one result. With several pairs of one data graph each and few results, as in `twolinks`, the pair nodes cost a few triples more than they save. Level 2 saves a constant per report, not per result.

## Logical constraints, blank nodes, `sh:node` and qualified shapes

What the captures show (`reports/*.ttl`):

| Case                                                          | `sh:sourceShape`                          | Component                                 | What is missing                                    |
|---------------------------------------------------------------|-------------------------------------------|-------------------------------------------|----------------------------------------------------|
| `sh:or ( [datatype string] [datatype integer] )`              | outer property shape                      | `sh:OrConstraintComponent`                | nothing for `or`: all members failed by definition |
| `sh:and ( [minLength 2] [maxLength 5] )`                      | outer property shape                      | `sh:AndConstraintComponent`               | which member failed (here `maxLength`)             |
| `sh:not [hasValue "none"]`                                    | outer property shape                      | `sh:NotConstraintComponent`               | nothing: the inner shape conformed                 |
| `sh:xone ( … )`                                               | no result at all                          |                                           | see side findings                                  |
| `sh:node ex:AddressShape`                                     | outer blank property shape                | `sh:NodeConstraintComponent`              | the nested postcode failure                        |
| `sh:qualifiedValueShape [class Wheel]`, `qualifiedMinCount 4` | outer blank property shape                | `sh:QualifiedMinCountConstraintComponent` | nothing essential                                  |
| blank `sh:property [ … ]`                                     | the blank node, shared by all its results | as failed                                 | a link to the stored node                          |

Pointing at the outer shape is correct. SHACL defines `sh:sourceShape` as the shape the focus node was validated against, and the constraint component belongs to that shape. The member that caused the failure is additional information, and SHACL already has a place for it: `sh:detail`, which the spec mentions explicitly for `sh:node`.

The hard part is naming a member without copying it. A member of an `sh:or` / `sh:and` / `sh:xone` list is just the node in `rdf:first`; a result can reference that node directly, with no need to copy the list. The problem is only that the node is usually blank. Three ways to address a blank shape, and their limits:

1.  **Parent and list index**, e.g. `ex:ItemSizeShape`, `sh:and`, member 2. Works for lists and for `sh:not`, but not for `sh:property`, whose values have no order, and two property shapes on the same path are common. The index changes when the list is edited. A nested member needs a chain of steps back to the nearest IRI.
2.  **Content hash**, a deterministic IRI computed from the canonical triples of the shape. Stable across reloads and works everywhere. Two identical blank shapes under different parents get the same id, and any edit gives a new id. GraphDB already hashes shapes internally (the recursive shape in `raw/recursive.nt` fails "while computing hashCode").
3.  **IRIs in the shapes graph.** The only fully reliable way, and the one to recommend to modellers for shapes whose results matter.

### Recommended scheme

- `sh:sourceShape` stays the shape that owns the failing constraint component, as today.
- IRI shapes are referenced, not copied (level 2).
- A blank source shape is copied once and completely. The copy carries `rsx:shapeId` (content hash) and, where it exists, `rsx:parentShape`, `rsx:parentProperty` (`sh:property`, `sh:and`, `sh:node`, …) and, for list members, `rsx:memberIndex`.
- When asked for, a result for `sh:and`, `sh:or` or `sh:node` gets `sh:detail` child results whose `sh:sourceShape` is the failing member, addressed the same way. For `sh:not` there is nothing to detail. This is optional because it makes reports larger.

```turtle
# sh:and result with detail (proposed)
_:r a sh:ValidationResult ;
    sh:focusNode ex:badSize ; sh:value "abcdefgh" ; sh:resultPath ex:size ;
    sh:sourceShape ex:ItemSizeShape ;
    sh:sourceConstraintComponent sh:AndConstraintComponent ;
    sh:detail [ a sh:ValidationResult ;
        sh:focusNode ex:badSize ; sh:value "abcdefgh" ;
        sh:sourceShape _:m2 ;
        sh:sourceConstraintComponent sh:MaxLengthConstraintComponent ] .
_:m2 sh:maxLength 5 ;
    rsx:parentShape ex:ItemSizeShape ; rsx:parentProperty sh:and ; rsx:memberIndex 2 ;
    rsx:shapeId <urn:rsx:shape:sha256:…> .
```

Limits: a blank shape used by two parents has two addresses but one id; `sh:property` members can only be found by id or by content; and recursive shapes, which references would handle without infinite copying, are rejected by GraphDB today.

## Compatibility with the W3C report vocabulary

- SHACL requires exactly one `sh:ValidationReport` and allows additional information in the report graph. Level 1 keeps one report and only moves `rsx:` properties, which are an RDF4J extension in the first place.
- Clients that read `rsx:dataGraph` from a result must follow one more step: `?result ^sh:result/rsx:dataGraph ?g` for a single pair, or `?result rsx:graphPair/rsx:dataGraph ?g` for several. A configuration flag could keep the old form for a transition period.
- `sh:sourceShape`, `sh:sourceConstraintComponent` and `sh:detail` are used as the spec defines them. Keeping a blank-node copy as the value of `sh:sourceShape`, rather than replacing it by a hash IRI, means that no standard consumer loses information.

## Side findings

- `sh:xone` is silently ignored. `ex:badColour2` ("blue") matches neither member of `sh:xone` and gets no result, and the copied `ex:ItemColourShape` has no `sh:xone`. RDF4J does not list `sh:xone` among supported predicates; an error at shape load time would be better.
- A recursive shape (`input/recursive.trig`) is rejected with "Recursive shape definition detected while computing hashCode".
- Without an `Accept` header the report comes as `application/shacl-validation-report+n-quads;charset=ISO-8859-1`.

## Reproduce

Each scenario is independent. It needs only its own `input/<case>.trig` and `links/<case>.ttl`, uses its own graphs, classes and focus nodes, and gives the same report on an empty repository as in a repository where all other scenarios are already loaded. Every link commit fails validation and is rolled back, so nothing is left in `rdf4j:SHACLShapeGraph` afterwards (`capture.sh` prints the count after each case). Shapes posted straight into `rdf4j:SHACLShapeGraph` validate every graph in the repository, so `plain` targets a class, `ex:PlainPerson`, that no other scenario uses. Both ways were checked: every case alone in a fresh repository, and all cases in sequence in one repository; `compare.py` found the raw reports identical up to blank-node labels.

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

## Files

- `repo-config.ttl`: repository config; every scenario's shapes graph is on `shacl:shapesGraph`.
- `input/<name>.trig`: shapes and data per scenario; `links/<name>.ttl`: the link that triggers validation (`plain.ttl` holds shapes for `rdf4j:SHACLShapeGraph` instead).
- `raw/`: reports exactly as GraphDB returned them (N-Triples), the GraphDB version, and the report without an `Accept` header plus its content type.
- `reports/<case>.ttl`: the raw report as formatted Turtle.
- `dry-reports/<case>-level1.ttl`, `-level2.ttl`: the same report rewritten into the two proposed forms by `measure.py`.
- `capture.sh`, `compare.py`, `measure.py`, `gen-fanout.py`, `measurements.md`.
