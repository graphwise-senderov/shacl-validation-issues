# Changing the SHACL shape graph list of an existing GraphDB repository

## Result

We suspected that GraphDB cannot change the `shacl:shapesGraph` list ("Named graphs for SHACL shapes") of an existing repository. The test below shows that it can. The change only takes effect after the repository is restarted, so this is not a bug.

- Editing the list with `PUT /rest/repositories/{id}` returns HTTP 200 and stores the new list, but validation keeps using the old list, even 30 seconds later.
- After `POST /rest/repositories/{id}/restart` the new list is active, and validation behaves like a repository created with that list.
- The RDF4J protocol route, `PUT /repositories/{id}` with a Turtle config, is rejected with HTTP 409 "repository already exists".

This matches the GraphDB documentation, which says that edited repository parameters take effect after a restart. In the Workbench this is the "Restart repository" box on the edit form. If the edit is saved without that box ticked, validation silently runs with the old list.

A second observation, which may deserve its own report, is in step 1 below. When the list holds any named graph besides `rdf4j:SHACLShapeGraph`, a `rsx:DataAndShapesGraphLink` also uses shapes from graphs that are not on the list.

## Environment

GraphDB Enterprise `12.0.0-SHACL-SIEMENS-RC1` (RDF4J `5.3.1-jakarta-Shacl-Improvements-TR1`, Workbench `4.0.0-TR5`). All data is synthetic.

## Files

| File | Purpose |
|------|---------|
| `repo-config.ttl` | Repository with the list `rdf4j:SHACLShapeGraph`, `ex:shapes/person`. |
| `repo-config-sail-only.ttl` | Repository with the list `rdf4j:SHACLShapeGraph` only. |
| `repo-config-extended.ttl` | Control repository whose list also has `ex:shapes/company`. |
| `happy/data.trig` | Person shapes in `ex:shapes/person`, people in `ex:data/people`. `ex:bob` has no name and `ex:carol` has a negative age. |
| `happy/link.ttl` | Link that validates `ex:data/people` against `ex:shapes/person`. |
| `unhappy/data.trig` | Company shapes in `ex:shapes/company`, companies in `ex:data/companies`. `ex:initech` has no name and employs a company instead of a person. |
| `unhappy/link.ttl` | Link that validates `ex:data/companies` against `ex:shapes/company`. |
| `extend-shapes-graphs.sh` | Tries to add `ex:shapes/company` to an existing repository: `put`, `restart` or `rdf4j-put`. |
| `common.sh` | Shared curl helpers. |
| `run-all.sh` | Runs every step below and deletes its repositories. |

Validation is triggered by uploading a link file into the graph `rdf4j:SHACLShapeGraph`. A link with violations is rejected with HTTP 500 and the SHACL report. A link without violations is committed with HTTP 204, so it is cleared again before the next attempt.

## Reproduction

```bash
export GDB_URL=http://localhost:7200 GDB_USER=admin GDB_PASSWORD=...
./run-all.sh shacl-graphs
```

The repositories can also be created by hand from the config files, via Workbench import or `POST /rest/repositories`.

1. Create a repository from `repo-config.ttl`. Upload `happy/data.trig`, then `happy/link.ttl`. Upload `unhappy/data.trig`, then `unhappy/link.ttl`.
2. Create a repository from `repo-config-sail-only.ttl`. Upload both payloads, then `unhappy/link.ttl`. Run each route of `extend-shapes-graphs.sh` and upload `unhappy/link.ttl` after each one.
3. Create a repository from `repo-config-extended.ttl`. Upload both payloads, then `unhappy/link.ttl`.

## Observed output (trimmed)

Step 1. The happy path finds both person errors. The company errors are also found, although `ex:shapes/company` is not on the list.

```
stored shapesGraph: http://example.org/shapes/person, http://rdf4j.org/schema/rdf4j#SHACLShapeGraph
link happy/link.ttl: HTTP 500, 2 violation(s)
    shacl#focusNode> <http://example.org/bob>     MinCountConstraintComponent
    shacl#focusNode> <http://example.org/carol>   MinInclusiveConstraintComponent
link unhappy/link.ttl: HTTP 500, 2 violation(s)
    shacl#focusNode> <http://example.org/initech> MinCountConstraintComponent
    shacl#focusNode> <http://example.org/initech> ClassConstraintComponent
```

Step 2. With the default list the errors are not found. The REST PUT stores the new list but changes nothing. After the restart the errors are found.

```
stored shapesGraph: http://rdf4j.org/schema/rdf4j#SHACLShapeGraph
link unhappy/link.ttl: HTTP 204, 0 violation(s)
PUT /repositories/...-sail-only: HTTP 409   (REPOSITORY EXISTS)
link unhappy/link.ttl: HTTP 204, 0 violation(s)
PUT /rest/repositories/...-sail-only: HTTP 200
stored shapesGraph: http://example.org/shapes/company, http://rdf4j.org/schema/rdf4j#SHACLShapeGraph
link unhappy/link.ttl: HTTP 204, 0 violation(s)      (30 s after the PUT)
POST /rest/repositories/...-sail-only/restart: HTTP 202
link unhappy/link.ttl: HTTP 500, 2 violation(s)
```

Step 3. The control repository finds the same two errors.

```
stored shapesGraph: http://example.org/shapes/company, http://example.org/shapes/person, http://rdf4j.org/schema/rdf4j#SHACLShapeGraph
link unhappy/link.ttl: HTTP 500, 2 violation(s)
```

## Expected and actual

| Action | Expected | Actual |
|--------|----------|--------|
| REST PUT of a longer list | Active, or rejected with a message that a restart is needed | HTTP 200 and stored, but inactive until restart |
| Repository restart after the PUT | Active | Active |
| RDF4J `PUT /repositories/{id}` | Config update | HTTP 409 |
| Link to a shapes graph that is not on the list | Ignored | Used, as long as the list holds any named graph besides `rdf4j:SHACLShapeGraph` |
