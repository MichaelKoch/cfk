# Confluent Platform for Apache Flink

Flink runs through CFK and Confluent Manager for Apache Flink (CMF). The operators and CMF come from the [operators chart](confluent-operators-chart.md) (namespace `confluent-operator`); each [platform instance](confluent-platform-chart.md) gets its own `CMFRestClass` and `FlinkEnvironment`. For ad-hoc SQL over REST see [sql-gateway.md](sql-gateway.md) (also Flink 1.19 `cp-flink-sql`; CMF SQL runs on 1.19, the only Confluent Flink SQL image line, CMF 2.4 supports Flink 2.x only for applications).

## How it fits together

```
CFK operator ──(CMFRestClass, FlinkEnvironment, FlinkApplication)──▶ CMF REST API (cmf-service.confluent-operator:80)
CMF ──(FlinkDeployment)──▶ CP Flink Kubernetes Operator ──▶ JobManager / TaskManager pods
```

| Part | Source | Notes |
|---|---|---|
| CP Flink Kubernetes Operator | operators chart, subchart `flink-kubernetes-operator` 1.150.4 (= 1.15.0-cp4) | Watches the instance namespaces; admission webhook needs cert-manager |
| CMF | operators chart, subchart `confluent-manager-for-apache-flink` 2.4.4 | Shared by all instances; SQLite on a PVC, no auth, trial license |
| `CMFRestClass` `cmf` | `templates/flink.yaml` | Points CFK at `http://cmf-service.<operatorNamespace>.svc.cluster.local:80` |
| `FlinkEnvironment` | `templates/flink.yaml` | Named after the instance namespace (CMF names are global); deploys applications into it |
| `FlinkApplication` (example) | `templates/flink.yaml` | `StateMachineExample` streaming job, stateless |
| Shared Flink SQL: `FlinkKafkaCatalog` `<ns>`, `FlinkKafkaDatabase` `kafka`, `FlinkComputePool` `shared` | `templates/flinksql.yaml` | Registered in CMF; catalog on Schema Registry, database on this instance's Kafka (`ddlEnvironments: [<env>]`), pool `DEDICATED` (each statement gets its own JobManager/TaskManager) |

## Prerequisite

cert-manager in the cluster (once):

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.21.2/cert-manager.yaml
```

## Key values

| Value | Default | Purpose |
|---|---|---|
| `confluent-for-kubernetes.enableFlinkSQL` (operators chart) | `true` | CFK reconciles `FlinkKafkaCatalog`, `FlinkKafkaDatabase`, `FlinkComputePool`, `FlinkStatement` |
| `flink.enabled` | `true` | Create `CMFRestClass` and `FlinkEnvironment` |
| `flink.environment` | `""` = release namespace | FlinkEnvironment name, unique across CMF |
| `flink.image` / `flink.flinkVersion` | `cp-flink:2.1.3-cp3-java21` / `v2_1` | Flink image and matching version for applications |
| `flink.exampleApplication.enabled` | `true` | Deploy the example job |
| `flink.exampleApplication.jobManager.resource` / `.taskManager.resource` | `cpu: 1, memory: 1024m` | `cpu` must be an integer or quantity string |
| `flink.sql.enabled` | `true` | Shared catalog, database and compute pool (needs Kafka and Schema Registry) |
| `flink.sql.catalog` / `.database` | `""` = namespace / `kafka` | Catalog name is global in CMF |
| `flink.sql.computePool.name` / `.image` / `.flinkVersion` | `shared` / `cp-flink-sql:1.19-cp12` / `v1_19` | Per-statement cluster spec |
| `flink.sql.computePool.jobManager.resource` / `.taskManager.resource` / `.flinkConfiguration` | `1 / 1024m`, `1 / 1536m`, 2 slots | Per statement; `cp-local`: `0.25 / 768m`, `0.5 / 1024m`, 1 slot, managed fraction 0.1 |
| `cmfNodePort` (operators chart) | `0` = off | Extra NodePort Service for the CMF REST API; `cp-local`: 30080 |

## Verify and use

```bash
kubectl get cmfrestclass,flinkenvironment,flinkapplication,flinkdeployment -n cp-local
kubectl port-forward -n <ns> svc/state-machine-rest 8081:8081                 # Flink UI of the example job (off in cp-local)
kubectl port-forward -n confluent-operator svc/cmf-service 8080:80   # CMF REST API, e.g. curl localhost:8080/cmf/api/v1/environments
local/cp-local-cluster.sh flink                                       # cp-local: CMF registration via http://<node-ip>:30080/cmf/api/v1
```

Add your own job as another `FlinkApplication` with `flinkEnvironment: <ns>` and `cmfRestClassRef.name: cmf`.

Run Flink SQL on the shared pool as a `FlinkStatement`:

```yaml
apiVersion: platform.confluent.io/v1beta1
kind: FlinkStatement
metadata: { name: my-query, namespace: cp-local }
spec:
  flinkEnvironment: cp-local
  cmfRestClassRef: { name: cmf }
  computePoolName: shared
  properties: { sql.current-catalog: cp-local, sql.current-database: kafka }
  statement: SELECT * FROM my_topic
```

The VS Code Confluent extension can't use it: its Flink features are Confluent Cloud only.

## End-to-end test (Flink SQL)

```bash
NS=cp-local tests/flink-e2e/run.sh   # KEEP=1 keeps statements/topics; FLINK_ENV, CATALOG, DATABASE, POOL default to the chart
```

Runs through CFK + CMF on the shared catalog, database and pool (waits until they are `CREATED`), then `FlinkStatement`s: `CREATE TABLE e2e_in/e2e_out` → continuous `INSERT INTO e2e_out SELECT id, UPPER(msg) FROM e2e_in` → bounded insert of 3 rows. It reads `e2e_out` with `kafka-avro-console-consumer`, expects `ALPHA/BETA/GAMMA` and prints `PASS`. Cleanup removes its statements, topics and subjects; the shared resources stay. The first run pulls the ~900 MB SQL image (several minutes).

## Notes

- Right after install, CFK logs `connection refused` for `cmf` until CMF is ready; it retries every 10 s, then creates the environment and applications.
- Removing a `FlinkApplication` deletes its `FlinkDeployment` and pods via CMF.
- The CMF PVC is kept on uninstall, like the other PVCs.
- Every `helm upgrade` restarts CMF (the chart's `rollme` annotation). CFK resources show `connection refused` for about a minute, then sync again; running Flink jobs keep running.
- `CREATE TABLE` in a Kafka database needs the environment listed in its `ddlEnvironments`.
- The `cp-flink` application image has no Kafka connector; for Kafka jobs use Flink SQL (compute pools) or ship the connector in your own JAR/image.
