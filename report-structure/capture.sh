#!/usr/bin/env bash
# Capture the raw validation reports.
#
#   ./capture.sh [--isolated] [case ...]
#
# Without --isolated, all cases run in sequence in one temporary repository.
# With --isolated, every case gets its own fresh repository. Each case uploads
# input/<case>.trig, then posts links/<case>.ttl into rdf4j:SHACLShapeGraph,
# which triggers validation; the failed commit returns the report, saved to
# $OUT/<case>.nt (default raw/). recursive.nt holds an error message, not a
# report: GraphDB rejects recursive shapes. Temporary repositories are deleted
# at the end.
#
# Needs GDB_URL (e.g. http://localhost:7200) and GDB_PASSWORD; GDB_USER
# defaults to admin.
set -euo pipefail
cd "$(dirname "$0")"
: "${GDB_URL:?set GDB_URL}"
CURL=(curl -sS -u "${GDB_USER:-admin}:${GDB_PASSWORD:?set GDB_PASSWORD}")
OUT="${OUT:-raw}"
PREFIX="tmp-shacl-report-structure-$(date +%Y%m%d)"
CTX='context=%3Chttp%3A%2F%2Frdf4j.org%2Fschema%2Frdf4j%23SHACLShapeGraph%3E'
ISOLATED=
if [[ "${1:-}" == --isolated ]]; then ISOLATED=1; shift; fi
CASES=("$@")
[[ ${#CASES[@]} -gt 0 ]] || CASES=(single-graph repeat fanout logic recursive)
mkdir -p "$OUT"
CREATED=()

create_repo() {
    sed "s/rep:repositoryID \"[^\"]*\"/rep:repositoryID \"$1\"/" repo-config.ttl > "$OUT/.config.ttl"
    "${CURL[@]}" -f -X POST -F "config=@$OUT/.config.ttl" "$GDB_URL/rest/repositories"
    rm "$OUT/.config.ttl"
    CREATED+=("$1")
}
cleanup() {
    for r in "${CREATED[@]}"; do
        "${CURL[@]}" -f -X DELETE "$GDB_URL/rest/repositories/$r" && echo "deleted $r" || echo "could not delete $r"
    done
}
trap cleanup EXIT

run_case() {  # run_case REPO CASE
    local repo=$1 s=$2 code
    "${CURL[@]}" -f -X POST -H 'Content-Type: application/trig' \
        --data-binary "@input/$s.trig" "$GDB_URL/repositories/$repo/statements"
    code=$("${CURL[@]}" -o "$OUT/$s.nt" -w '%{http_code}' -X POST \
        -H 'Content-Type: text/turtle' -H 'Accept: application/n-triples' \
        --data-binary "@links/$s.ttl" "$GDB_URL/repositories/$repo/statements?$CTX")
    echo "$s: HTTP $code, $(wc -c < "$OUT/$s.nt") bytes, $(shape_graph_size "$repo") statements left in rdf4j:SHACLShapeGraph"
    if [[ $s == single-graph ]]; then
        # The same report without an Accept header, to show the default format.
        "${CURL[@]}" -o "$OUT/single-graph-default.out" -w '%{content_type}\n' -X POST \
            -H 'Content-Type: text/turtle' --data-binary @links/single-graph.ttl \
            "$GDB_URL/repositories/$repo/statements?$CTX" > "$OUT/single-graph-default.content-type"
    fi
}
shape_graph_size() {
    "${CURL[@]}" "$GDB_URL/repositories/$1/size?$CTX"
}

curl -sS "$GDB_URL/rest/info/version" > "$OUT/graphdb-version.json"
if [[ -n $ISOLATED ]]; then
    for s in "${CASES[@]}"; do
        create_repo "$PREFIX-$s"
        run_case "$PREFIX-$s" "$s"
    done
else
    create_repo "$PREFIX"
    for s in "${CASES[@]}"; do run_case "$PREFIX" "$s"; done
fi
