# Shared settings and helpers. Source this file; do not run it.
# Set GDB_URL (e.g. http://localhost:7200), GDB_USER and GDB_PASSWORD.
: "${GDB_URL:?set GDB_URL}"
GDB_USER="${GDB_USER:-admin}"
CURL=(curl -sS -u "$GDB_USER:${GDB_PASSWORD:?set GDB_PASSWORD}")
SHAPE_GRAPH='<http://rdf4j.org/schema/rdf4j#SHACLShapeGraph>'
SHAPE_GRAPH_PARAM='context=%3Chttp%3A%2F%2Frdf4j.org%2Fschema%2Frdf4j%23SHACLShapeGraph%3E'

# create_repo CONFIG_TTL REPO_ID: create a repository from a config file,
# replacing its repositoryID with REPO_ID.
create_repo() {
    sed "s/rep:repositoryID \"[^\"]*\"/rep:repositoryID \"$2\"/" "$1" > /tmp/config-$2.ttl
    "${CURL[@]}" -o /dev/null -w "create $2: HTTP %{http_code}\n" \
        -X POST -F "config=@/tmp/config-$2.ttl" "$GDB_URL/rest/repositories"
}

# upload REPO FILE.trig: add a TriG payload.
upload() {
    "${CURL[@]}" -o /dev/null -w "upload $2: HTTP %{http_code}\n" \
        -X POST -H 'Content-Type: application/trig' --data-binary "@$2" \
        "$GDB_URL/repositories/$1/statements"
}

# link REPO FILE.ttl: add a link into rdf4j:SHACLShapeGraph, which triggers
# validation. A rejected commit returns HTTP 500 with the SHACL report
# (N-Triples), saved to /tmp/report.nt.
link() {
    local code
    code=$("${CURL[@]}" -o /tmp/report.nt -w '%{http_code}' \
        -X POST -H 'Content-Type: text/turtle' --data-binary "@$2" \
        "$GDB_URL/repositories/$1/statements?$SHAPE_GRAPH_PARAM")
    echo "link $2: HTTP $code, $(grep -c 'rdf-syntax-ns#type> <http://www.w3.org/ns/shacl#ValidationResult>' /tmp/report.nt) violation(s)"
    grep -oE 'shacl#(focusNode|sourceConstraintComponent)> <[^>]*>' /tmp/report.nt | sed 's/^/    /' || true
}

# unlink REPO: clear rdf4j:SHACLShapeGraph so later links start clean.
unlink() {
    "${CURL[@]}" -o /dev/null -w "clear SHACLShapeGraph: HTTP %{http_code}\n" \
        -X POST -H 'Content-Type: application/sparql-update' \
        --data "CLEAR GRAPH $SHAPE_GRAPH" "$GDB_URL/repositories/$1/statements"
}

# shapes_graphs REPO: print the stored shacl:shapesGraph allow-list.
shapes_graphs() {
    "${CURL[@]}" -H 'Accept: application/json' "$GDB_URL/rest/repositories/$1" |
        python3 -c 'import json,sys; print("stored shapesGraph:", json.load(sys.stdin)["params"]["shapesGraph"]["value"])'
}

# delete_repo REPO
delete_repo() {
    "${CURL[@]}" -o /dev/null -w "delete $1: HTTP %{http_code}\n" -X DELETE "$GDB_URL/rest/repositories/$1"
}
