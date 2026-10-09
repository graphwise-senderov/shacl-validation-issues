#!/usr/bin/env bash
# End-to-end run. Creates three repositories named $PREFIX-*, runs every
# step, and deletes them again. Usage: run-all.sh [PREFIX]
set -euo pipefail
cd "$(dirname "$0")"
source common.sh
P=${1:-shacl-graphs}
A=$P-listed B=$P-sail-only C=$P-control

echo "== 1. List = SHACLShapeGraph + shapes/person"
create_repo repo-config.ttl "$A"; shapes_graphs "$A"
upload "$A" happy/data.trig
link "$A" happy/link.ttl
upload "$A" unhappy/data.trig
echo "shapes/company is not on the list:"
link "$A" unhappy/link.ttl

echo; echo "== 2. List = SHACLShapeGraph only, then extended"
create_repo repo-config-sail-only.ttl "$B"; shapes_graphs "$B"
upload "$B" happy/data.trig
upload "$B" unhappy/data.trig
link "$B" unhappy/link.ttl; unlink "$B"
./extend-shapes-graphs.sh "$B" rdf4j-put || true
link "$B" unhappy/link.ttl; unlink "$B"
./extend-shapes-graphs.sh "$B" put
sleep 30
link "$B" unhappy/link.ttl; unlink "$B"
./extend-shapes-graphs.sh "$B" restart
sleep 5
link "$B" unhappy/link.ttl; unlink "$B"

echo; echo "== 3. Control: fresh repository created with the extended list"
create_repo repo-config-extended.ttl "$C"; shapes_graphs "$C"
upload "$C" happy/data.trig
upload "$C" unhappy/data.trig
link "$C" unhappy/link.ttl

echo
for r in "$A" "$B" "$C"; do delete_repo "$r"; done
