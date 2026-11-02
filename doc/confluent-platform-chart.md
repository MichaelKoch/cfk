# Confluent Platform chart

Chart [charts/confluent-platform](../charts/confluent-platform): **one KRaft-based Confluent Platform instance per namespace**, sized for minikube. It contains no operators; it needs the [operators chart](confluent-operators-chart.md) watching the target namespace.

## What it deploys

| Component | Kind | Default replicas | Image |
|---|---|---|---|
| KRaft controller | `KRaftController` | 1 | `cp-server` |
| Kafka brokers | `Kafka` | 3 | `cp-server` |
| Schema Registry | `SchemaRegistry` | 1 | `cp-schema-registry` |
| Connect | `Connect` | 1 | `cp-server-connect` |
| ksqlDB | `KsqlDB` | 1 | `cp-ksqldb-server` |
| REST Proxy | `KafkaRestProxy` | 1 | `cp-kafka-rest` |
| Control Center (next gen) + Prometheus + Alertmanager | `ControlCenter` | 1 | `cp-enterprise-control-center-next-gen` |
| Flink environment + example job (via CMF) | `CMFRestClass`, `FlinkEnvironment`, `FlinkApplication` | 1 JM + 1 TM | `cp-flink` |
| Flink SQL Gateway + session cluster (Flink 1.19) | `Deployment`, `FlinkDeployment` | 1 + 1 JM | `cp-flink-sql` (Kafka, Avro connectors included) |

CP `8.2.4`, init container `3.3.1`, Control Center `2.6.1`. No security (plaintext, no auth). Not for production.

## Instances

Per-instance overrides live in [environments/](../environments):

| Release / namespace | Values | Content |
|---|---|---|
| `cp-local` | `environments/cp-local.yaml` | Kafka (1 broker), Schema Registry, Control Center, Flink environment, SQL Gateway; reduced resources, runs in the isolated local cluster ([local-cluster.md](local-cluster.md)) |

## Install / remove

```bash
helm upgrade --install cp-local charts/confluent-platform -n cp-local -f environments/cp-local.yaml
kubectl get confluent -n cp-local

# Remove: CRs first so the operators can clear their finalizers
kubectl delete flinkapplications --all -n cp-local --wait
kubectl delete flinkenvironments --all -n cp-local --wait   # before cmfrestclasses, or CFK can't reach CMF and the finalizer hangs
kubectl delete cmfrestclasses --all -n cp-local --wait
kubectl delete flinkdeployment sql-gateway-session -n cp-local --wait
kubectl delete confluent --all -n cp-local --wait
helm uninstall cp-local -n cp-local
kubectl delete pvc --all -n cp-local   # PVCs are kept otherwise
```

## Key values

| Value | Default | Purpose |
|---|---|---|
| `operatorNamespace` | `confluent-operator` | Where CMF runs (`CMFRestClass` endpoint) |
| `platform.version` | `8.2.4` | CP image tag for all components |
| `platform.initImage` | `confluent-init-container:3.3.1` | Must match the CFK version |
| `platform.storageClass` | `local-path` | Node-local volumes. minikube `standard` (hostpath) fails on multi-node clusters: volumes land on the wrong node and are not writable for uid 1001 |
| `platform.externalHost` | `""` | Node IP/hostname; when set, Kafka gets an external NodePort listener and Schema Registry a NodePort (access from outside the cluster) |
| `kafka.externalNodePortOffset` | `30000` | Bootstrap `<host>:30000`, broker N on `30001+N` |
| `schemaRegistry.externalNodePort` | `30081` | `http://<host>:30081` |
| `<component>.enabled` | `true` | Toggle each component |
| `<component>.replicas` / `.resources` / `.dataVolumeCapacity` | see `values.yaml` | Sizing |
| `kafka.configOverrides` | `[]` | Extra broker properties (`configOverrides.server`), e.g. replication factor 1 for a single broker |
| `controlCenter.configOverrides` | `[]` | Extra Control Center properties, e.g. internal topic replication factor 1 for a single broker |
| `controlCenter.version` | `2.6.1` | C3, Prometheus and Alertmanager image tag |

Component keys: `kraftController`, `kafka`, `schemaRegistry`, `connect`, `ksqldb`, `kafkaRestProxy`, `controlCenter`. Flink: [flink.md](flink.md). SQL Gateway: [sql-gateway.md](sql-gateway.md).

## Notes

- Keep `kafka.replicas` at 3 or more, unless `kafka.configOverrides` lowers the replication factors (as in `cp-local`): internal topics default to replication factor 3.
- When Control Center is enabled, KRaft and Kafka push metrics to its Prometheus (`metricsClient` dependency).
- Control Center UI: `local/cp-local-cluster.sh ui` (or `kubectl port-forward -n cp-local svc/controlcenter 9021:9021`) → http://localhost:9021.
- Service URLs inside an instance: `<component>.<ns>.svc.cluster.local` (e.g. `kafka.cp-local.svc.cluster.local:9071`).
