#!/usr/bin/env bash
# Flink SQL end-to-end test through CFK + CMF on the chart's shared catalog/database/compute pool:
# CREATE TABLE e2e_in/e2e_out -> continuous INSERT INTO e2e_out SELECT id, UPPER(msg) FROM e2e_in ->
# bounded insert of 3 rows -> read e2e_out from Kafka and compare.
# Cleans up its statements, topics and subjects afterwards (KEEP=1 keeps them).
set -euo pipefail

NS=${NS:-cp-local}
FLINK_ENV=${FLINK_ENV:-$NS} # chart default: FlinkEnvironment named after the namespace
CATALOG=${CATALOG:-$NS}     # chart default: flink.sql.catalog = namespace
DATABASE=${DATABASE:-kafka} # flink.sql.database
POOL=${POOL:-shared}        # flink.sql.computePool.name
DIR=$(cd "$(dirname "$0")" && pwd)
EXPECTED=$'1 ALPHA\n2 BETA\n3 GAMMA'
k() { kubectl ${CONTEXT:+--context "$CONTEXT"} -n "$NS" "$@"; }
# render <step>: manifest with environment, catalog, database and pool filled in
render() {
  sed -e "s/__FLINK_ENV__/$FLINK_ENV/g" -e "s/__CATALOG__/$CATALOG/g" -e "s/__DATABASE__/$DATABASE/g" \
    -e "s/__POOL__/$POOL/g" "$DIR/$1.yaml"
}

cleanup() {
  echo "--- cleanup"
  for f in 03-produce 02-transform 01-tables; do render $f | k delete --ignore-not-found --wait -f - >/dev/null; done
  for t in e2e_in e2e_out; do
    k exec kafka-0 -c kafka -- sh -c "LOG_DIR=/tmp kafka-topics --bootstrap-server localhost:9071 --delete --if-exists --topic $t" >/dev/null 2>&1 || true
    k exec schemaregistry-0 -c schemaregistry -- sh -c \
      "curl -sf -X DELETE localhost:8081/subjects/$t-value && curl -sf -X DELETE 'localhost:8081/subjects/$t-value?permanent=true'" >/dev/null 2>&1 || true
  done
}

# wait_phase <phase> <timeout> <statement...>
wait_phase() {
  local phase=$1 timeout=$2; shift 2
  for s in "$@"; do
    if ! k wait --for=jsonpath="{.status.phase}=$phase" "flinkstatement/$s" --timeout="$timeout" >/dev/null; then
      echo "FAIL: statement $s did not reach $phase: $(k get flinkstatement "$s" -o jsonpath='{.status.phase} {.status.detail}')"
      exit 1
    fi
    echo "ok: $s $phase"
  done
}

cleanup
[[ "${KEEP:-0}" == 1 ]] || trap cleanup EXIT

echo "--- 1/4 shared catalog, database, compute pool (chart flink.sql)"
k wait --for=jsonpath='{.status.cfkInternalState}=CREATED' \
  "flinkkafkacatalog/$CATALOG" "flinkkafkadatabase/$DATABASE" "flinkcomputepool/$POOL" --timeout=180s

echo "--- 2/4 tables"
render 01-tables | k apply -f - >/dev/null
wait_phase COMPLETED 180s e2e-create-in e2e-create-out

echo "--- 3/4 transform (first run pulls the ~900 MB cp-flink-sql image)"
render 02-transform | k apply -f - >/dev/null
wait_phase RUNNING 600s e2e-transform

echo "--- 4/4 produce"
render 03-produce | k apply -f - >/dev/null
wait_phase COMPLETED 600s e2e-produce

echo "--- verify e2e_out"
actual=$(k exec schemaregistry-0 -c schemaregistry -- sh -c \
  'LOG_DIR=/tmp timeout 90 kafka-avro-console-consumer --bootstrap-server kafka:9071 --topic e2e_out \
     --from-beginning --max-messages 3 --formatter-property schema.registry.url=http://localhost:8081 2>/dev/null' \
  | sed -E 's/.*"id":\{"int":([0-9]+)\}.*"msg":\{"string":"([^"]*)"\}.*/\1 \2/' | sort)
echo "$actual"
if [[ "$actual" == "$EXPECTED" ]]; then
  echo "PASS: Flink SQL e2e"
else
  echo "FAIL: expected"; echo "$EXPECTED"; exit 1
fi
