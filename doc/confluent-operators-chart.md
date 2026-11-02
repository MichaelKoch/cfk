# Operators chart

Chart [charts/confluent-operators](../charts/confluent-operators), installed **once** into `confluent-operator`. It runs the operators shared by all Confluent Platform instances and creates the instance namespaces.

```
confluent-operator   CFK operator, CP Flink Kubernetes Operator, CMF (cmf-service:80)
cp-local             one confluent-platform release per instance namespace (see confluent-platform-chart.md)
```

| Part | Subchart | Scope |
|---|---|---|
| CFK operator | `confluent-for-kubernetes` 0.1718.99 (CFK 3.3.1) | Reconciles only `instanceNamespaces` (`namespaceList`); RBAC is a ClusterRole (upstream behaviour with a namespace list); `enableFlinkSQL: true` |
| CP Flink Kubernetes Operator | `flink-kubernetes-operator` 1.150.4 (1.15.0-cp4) | `watchNamespaces`; creates the `flink` job service account in each; webhook limited to those namespaces |
| CMF | `confluent-manager-for-apache-flink` 2.4.4 | One Role per namespace (`watchNamespaces`); shared by all instances, trial license, SQLite on a PVC |

## Install

Prerequisites (once per cluster): `minikube addons enable storage-provisioner-rancher` and cert-manager (see [flink.md](flink.md)).

```bash
helm repo add confluentinc https://packages.confluent.io/helm
helm dependency update charts/confluent-operators
helm upgrade --install confluent-operators charts/confluent-operators -n confluent-operator --create-namespace
```

## Key values

| Value | Default | Purpose |
|---|---|---|
| `instanceNamespaces` | `[cp-local]` | Namespaces created and watched. A YAML anchor feeds the three watch lists in `values.yaml`; when overriding from another file, also set `confluent-for-kubernetes.namespaceList`, `flink-kubernetes-operator.watchNamespaces` and `confluent-manager-for-apache-flink.watchNamespaces` |
| `flink-kubernetes-operator.enabled` / `confluent-manager-for-apache-flink.enabled` | `true` | Flink support |
| `cmfNodePort` | `0` = off | Extra NodePort Service `cmf-service-np` for the CMF REST API (local tools) |

The local cluster installs it with [environments/operators-cp-local.yaml](../environments/operators-cp-local.yaml) (reduced requests); see [local-cluster.md](local-cluster.md).

## Adding an instance namespace

1. Add it to `instanceNamespaces` and `helm upgrade` this chart (creates namespace, Roles and the `flink` service account).
2. Add `environments/<ns>.yaml` and install the platform chart there.

## Notes

- Namespaces have `helm.sh/resource-policy: keep`: uninstalling the operators never deletes an instance.
- Remove instances (CRs first) before uninstalling the operators; otherwise CR finalizers and the Flink webhook can block deletion.
- CMF environment names are global: each instance uses its namespace name as `FlinkEnvironment`.
- Watch scope vs. RBAC: Flink operator and CMF get Roles only in the instance namespaces. CFK reconciles only those namespaces, but the upstream chart binds a cluster-wide ClusterRole whenever `namespaceList` is set (restricting it would need `rbac: false` and self-managed Roles).
