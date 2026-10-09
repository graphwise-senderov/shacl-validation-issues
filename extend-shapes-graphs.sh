#!/usr/bin/env bash
# Try to add http://example.org/shapes/company to the shacl:shapesGraph
# allow-list of an existing repository.
# Usage: extend-shapes-graphs.sh REPO ROUTE
#   put       PUT /rest/repositories/REPO with the edited JSON config
#             (what the Workbench "Edit repository" page sends).
#   restart   POST /rest/repositories/REPO/restart.
#   rdf4j-put PUT /repositories/REPO with repo-config-extended.ttl
#             (RDF4J protocol repository config update).
set -euo pipefail
cd "$(dirname "$0")"
source common.sh
REPO=$1
NEW=http://example.org/shapes/company

case $2 in
put)
    "${CURL[@]}" -H 'Accept: application/json' "$GDB_URL/rest/repositories/$REPO" |
        python3 -c 'import json,sys
c = json.load(sys.stdin)
c["params"]["shapesGraph"]["value"] += ", " + sys.argv[1]
json.dump(c, sys.stdout)' "$NEW" > /tmp/config-$REPO.json
    "${CURL[@]}" -o /dev/null -w "PUT /rest/repositories/$REPO: HTTP %{http_code}\n" \
        -X PUT -H 'Content-Type: application/json' --data-binary "@/tmp/config-$REPO.json" \
        "$GDB_URL/rest/repositories/$REPO"
    ;;
restart)
    "${CURL[@]}" -w "\nPOST /rest/repositories/$REPO/restart: HTTP %{http_code}\n" \
        -X POST "$GDB_URL/rest/repositories/$REPO/restart"
    ;;
rdf4j-put)
    sed "s/rep:repositoryID \"[^\"]*\"/rep:repositoryID \"$REPO\"/" repo-config-extended.ttl > /tmp/config-$REPO.ttl
    "${CURL[@]}" -w "\nPUT /repositories/$REPO: HTTP %{http_code}\n" \
        -X PUT -H 'Content-Type: text/turtle' --data-binary "@/tmp/config-$REPO.ttl" \
        "$GDB_URL/repositories/$REPO"
    ;;
esac
shapes_graphs "$REPO"
