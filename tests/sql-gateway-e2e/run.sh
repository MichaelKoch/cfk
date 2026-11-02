#!/usr/bin/env bash
# Flink SQL Gateway end-to-end test, only through the gateway REST API:
# CREATE TABLE on a Kafka topic -> INSERT 3 rows (job on the session cluster) ->
# bounded SELECT back through the gateway and compare. Cleans up the topic afterwards.
set -euo pipefail

NS=${NS:-cp-local}
PORT=${PORT:-18083}
TOPIC=sgw_e2e
EXPECTED=$'1 ALPHA\n2 BETA\n3 GAMMA'
GW=http://localhost:$PORT/v1
k() { kubectl ${CONTEXT:+--context "$CONTEXT"} -n "$NS" "$@"; }

delete_topic() {
  k exec kafka-0 -c kafka -- sh -c "LOG_DIR=/tmp kafka-topics --bootstrap-server localhost:9071 --delete --if-exists --topic $TOPIC" >/dev/null 2>&1 || true
}

k port-forward svc/sql-gateway "$PORT:8083" >/dev/null 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true; delete_topic' EXIT
for _ in $(seq 30); do curl -sf "$GW/info" >/dev/null && break; sleep 1; done
echo "gateway: $(curl -sf "$GW/info")"

delete_topic
# the plain kafka connector does not create topics and broker auto-creation is off
k exec kafka-0 -c kafka -- sh -c "LOG_DIR=/tmp kafka-topics --bootstrap-server localhost:9071 --create --topic $TOPIC --partitions 1" >/dev/null
SESSION=$(curl -sf -X POST "$GW/sessions" -H 'Content-Type: application/json' -d '{}' | jq -r .sessionHandle)

# run <sql>: submit a statement and wait until it is finished; prints the operation handle
run() {
  local op status
  op=$(jq -n --arg s "$1" '{statement: $s}' | curl -sf -X POST "$GW/sessions/$SESSION/statements" \
    -H 'Content-Type: application/json' -d @- | jq -r .operationHandle)
  for _ in $(seq 300); do
    status=$(curl -sf "$GW/sessions/$SESSION/operations/$op/status" | jq -r .status)
    case $status in
      FINISHED) echo "$op"; return ;;
      ERROR | CANCELED | CLOSED)
        echo "FAIL: '$1' -> $status" >&2
        curl -s "$GW/sessions/$SESSION/operations/$op/result/0" | jq -r '.errors[]?' | head -20 >&2
        exit 1 ;;
    esac
    sleep 1
  done
  echo "FAIL: timeout on '$1'" >&2; exit 1
}

# fetch <op>: all result rows of a finished query, one "f1 f2" line per row
fetch() {
  local url="$GW/sessions/$SESSION/operations/$1/result/0" page
  while [[ -n "$url" ]]; do
    page=$(curl -sf "$url")
    jq -r '.results.data[]? | select(.kind == "INSERT") | .fields | map(tostring) | join(" ")' <<<"$page"
    case $(jq -r .resultType <<<"$page") in
      EOS) return ;;
      NOT_READY | PAYLOAD) url="http://localhost:$PORT$(jq -r .nextResultUri <<<"$page")"; sleep 0.5 ;;
      *) return ;;
    esac
  done
}

echo "--- 1/3 create table"
run "CREATE TABLE $TOPIC (id INT, msg STRING) WITH (
  'connector' = 'kafka', 'topic' = '$TOPIC',
  'properties.bootstrap.servers' = 'kafka.$NS.svc.cluster.local:9071',
  'properties.group.id' = 'sgw-e2e', 'format' = 'json',
  'scan.startup.mode' = 'earliest-offset', 'scan.bounded.mode' = 'latest-offset')" >/dev/null
echo "ok"

echo "--- 2/3 insert (job on sql-gateway-session; first job starts a TaskManager)"
run "SET 'table.dml-sync' = 'true'" >/dev/null
run "INSERT INTO $TOPIC VALUES (1, 'ALPHA'), (2, 'BETA'), (3, 'GAMMA')" >/dev/null
echo "ok"

echo "--- 3/3 bounded select"
run "SET 'execution.runtime-mode' = 'batch'" >/dev/null
actual=$(fetch "$(run "SELECT id, msg FROM $TOPIC")" | sort)
echo "$actual"
curl -sf -X DELETE "$GW/sessions/$SESSION" >/dev/null || true

if [[ "$actual" == "$EXPECTED" ]]; then
  echo "PASS: SQL Gateway e2e"
else
  echo "FAIL: expected"; echo "$EXPECTED"; exit 1
fi
