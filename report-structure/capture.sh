#!/usr/bin/env bash
# Reproduce the captures in captures/. Needs GDB_URL (e.g. http://localhost:7200)
# and GDB_PASSWORD; GDB_USER defaults to admin. Creates a temporary repository,
# runs each scenario, saves the raw report, and deletes the repository.
set -euo pipefail
cd "$(dirname "$0")"
: "${GDB_URL:?set GDB_URL}"
CURL=(curl -sS -u "${GDB_USER:-admin}:${GDB_PASSWORD:?set GDB_PASSWORD}")
REPO="${REPO:-tmp-shacl-report-structure-$(date +%Y%m%d)}"
CTX='context=%3Chttp%3A%2F%2Frdf4j.org%2Fschema%2Frdf4j%23SHACLShapeGraph%3E'

curl -sS "$GDB_URL/rest/info/version" > captures/graphdb-version.json
sed "s/rep:repositoryID \"[^\"]*\"/rep:repositoryID \"$REPO\"/" repo-config.ttl > "captures/.config.ttl"
"${CURL[@]}" -f -X POST -F "config=@captures/.config.ttl" "$GDB_URL/rest/repositories"
rm captures/.config.ttl
trap '"${CURL[@]}" -X DELETE "$GDB_URL/rest/repositories/$REPO"; echo "deleted $REPO"' EXIT

# recursive.nt holds an error message, not a report: GraphDB rejects recursive shapes.
for s in plain simple repeat fanout logic bnode node qualified recursive twolinks; do
    "${CURL[@]}" -f -X POST -H 'Content-Type: application/trig' \
        --data-binary "@input/$s.trig" "$GDB_URL/repositories/$REPO/statements"
    # Adding the link (or, for plain, the shapes) triggers validation. A failed
    # commit returns the validation report as the error body.
    code=$("${CURL[@]}" -o "captures/$s.nt" -w '%{http_code}' -X POST \
        -H 'Content-Type: text/turtle' -H 'Accept: application/n-triples' \
        --data-binary "@links/$s.ttl" "$GDB_URL/repositories/$REPO/statements?$CTX")
    echo "$s: HTTP $code, $(wc -c < "captures/$s.nt") bytes"
done

# The same simple report without an Accept header, to show the default format.
"${CURL[@]}" -o captures/simple-default.out -w '%{content_type}\n' -X POST \
    -H 'Content-Type: text/turtle' --data-binary @links/simple.ttl \
    "$GDB_URL/repositories/$REPO/statements?$CTX" > captures/simple-default.content-type
