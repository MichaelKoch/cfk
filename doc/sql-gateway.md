# Flink SQL Gateway

Each platform instance runs an Apache Flink SQL Gateway (`templates/sqlgateway.yaml`), toggled by `sqlGateway.enabled`.

```
client ──REST :8083──▶ sql-gateway (Deployment + Service)
sql-gateway ──execution.target=remote──▶ sql-gateway-session-rest:8081 (FlinkDeployment, session mode)
```

| Part | Kind | Notes |
|---|---|---|
| `sql-gateway` | `Deployment` + `Service` | `sql-gateway.sh start-foreground`, REST endpoint on 8083 |
| `sql-gateway-session` | `FlinkDeployment` (session mode) | Reconciled by the CP Flink Kubernetes Operator directly (not CMF); TaskManagers start on demand |

Flink **1.19** (`cp-flink-sql:1.19-cp12`, `v1_19`) for both: the Confluent-supported Flink SQL image, the same line CMF SQL uses. It ships the `kafka`, `upsert-kafka` and `avro-confluent` connectors; `json` is built in. `sqlGateway.extraJars` (default `[]`) can add jars: an init container (`curlimages/curl`) downloads them from the given URLs at pod start and mounts them into `/opt/flink/lib` (gateway, JobManager, TaskManagers). This is separate from CMF SQL (`FlinkStatement`, see [flink.md](flink.md)): gateway tables live in the in-memory default catalog of the session.

## Use

```bash
kubectl port-forward -n cp-local svc/sql-gateway 8083:8083
curl localhost:8083/v1/info
```

Any SQL Gateway REST client works (e.g. `sql-client.sh gateway --endpoint localhost:8083`, JDBC driver, DBeaver). Kafka bootstrap from inside the cluster: `kafka.<ns>.svc.cluster.local:9071`. Create topics before writing: the `kafka` connector doesn't create them and broker auto-creation is off.

## End-to-end test

```bash
NS=cp-local tests/sql-gateway-e2e/run.sh
```

Only via the REST API: `CREATE TABLE` (kafka, json) → `INSERT` of 3 rows (job on `sql-gateway-session`) → bounded batch `SELECT`; expects `ALPHA/BETA/GAMMA`, prints `PASS`, deletes the topic.

## Key values

| Value | Default | Purpose |
|---|---|---|
| `sqlGateway.enabled` | `true` | Deploy gateway and session cluster |
| `sqlGateway.image` / `.flinkVersion` | `cp-flink-sql:1.19-cp12` / `v1_19` | Must match each other |
| `sqlGateway.extraJars` | `[]` | Extra jar URLs downloaded at pod start; match the jar versions to the Flink version (only needed for images without connectors, e.g. `cp-flink`) |
| `sqlGateway.jarLoaderImage` | `curlimages/curl:8.20.0` | Init container that downloads the jars |
| `sqlGateway.resources` | `1Gi` | Gateway pod |
| `sqlGateway.session.jobManager` / `.taskManager` / `.flinkConfiguration` | `1 CPU / 1024m`, `1 CPU / 1536m`, 2 slots | Session cluster |
