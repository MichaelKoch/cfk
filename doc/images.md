# Container images

All images used by the local environment, with versions and where each version is set. "cp-local" = on in [environments/cp-local.yaml](../environments/cp-local.yaml); "off" = in the chart but disabled in cp-local.

## Operators (namespace `confluent-operator`)

Pinned through the subchart versions in [charts/confluent-operators/Chart.yaml](../charts/confluent-operators/Chart.yaml) (image tags are the subcharts' defaults).

| Image | Version | Component | Set by |
|---|---|---|---|
| `confluentinc/confluent-operator` | 0.1718.99 (CFK 3.3.1) | CFK operator | `confluent-for-kubernetes` 0.1718.99 |
| `confluentinc/cp-flink-kubernetes-operator` | 1.15.0-cp4 | CP Flink Kubernetes Operator | `flink-kubernetes-operator` 1.150.4 |
| `confluentinc/cp-cmf` | 2.4.4 | Confluent Manager for Apache Flink | `confluent-manager-for-apache-flink` 2.4.4 |

## Confluent Platform (namespace `cp-local`)

Set in [charts/confluent-platform/values.yaml](../charts/confluent-platform/values.yaml).

| Image | Version | Component | cp-local | Set by |
|---|---|---|---|---|
| `confluentinc/cp-server` | 8.2.4 | KRaft controller, Kafka broker | on | `platform.version` |
| `confluentinc/cp-schema-registry` | 8.2.4 | Schema Registry | on | `platform.version` |
| `confluentinc/cp-server-connect` | 8.2.4 | Kafka Connect | off | `platform.version` |
| `confluentinc/cp-ksqldb-server` | 8.2.4 | ksqlDB | off | `platform.version` |
| `confluentinc/cp-kafka-rest` | 8.2.4 | REST Proxy | off | `platform.version` |
| `confluentinc/confluent-init-container` | 3.3.1 | Init container of every CP component (matches CFK 3.3.1) | on | `platform.initImage` |
| `confluentinc/cp-enterprise-control-center-next-gen` | 2.6.1 | Control Center | on | `controlCenter.version` |
| `confluentinc/cp-enterprise-prometheus` | 2.6.1 | Control Center metrics | on | `controlCenter.version` |
| `confluentinc/cp-enterprise-alertmanager` | 2.6.1 | Control Center alerts | on | `controlCenter.version` |
| `confluentinc/cp-flink-sql` | 1.19-cp12 (Flink 1.19) | CMF shared compute pool (statement JM/TM) | on | `flink.sql.computePool.image` |
| `confluentinc/cp-flink-sql` | 1.19-cp12 (Flink 1.19) | SQL Gateway and its session cluster (JM/TM) | on | `sqlGateway.image` |
| `confluentinc/cp-flink` | 2.1.3-cp3-java21 (Flink 2.1) | Example `FlinkApplication` | off | `flink.image` |
| `curlimages/curl` | 8.20.0 | SQL Gateway jar loader init container, only if `sqlGateway.extraJars` is set | off (`extraJars: []`) | `sqlGateway.jarLoaderImage` |

## Cluster (installed by `local/cp-local-cluster.sh up`)

| Image | Version | Component | Set by |
|---|---|---|---|
| `gcr.io/k8s-minikube/kicbase` | v0.0.51 | minikube node container (Docker host) | minikube version (v1.39.0) |
| `registry.k8s.io/kube-apiserver`, `-controller-manager`, `-scheduler`, `-proxy` | v1.37.0 | Kubernetes control plane | `K8S_VERSION` |
| `registry.k8s.io/etcd` | 3.7.0-0 | etcd | minikube for v1.37.0 |
| `registry.k8s.io/coredns/coredns` | v1.14.6 | DNS | minikube for v1.37.0 |
| `docker.io/kindest/kindnetd` | v20260820-69b56db7 | CNI | minikube |
| `gcr.io/k8s-minikube/storage-provisioner` | v5 | minikube default storage provisioner | minikube |
| `docker.io/rancher/local-path-provisioner` | v0.0.22 | Storage class `local-path` (addon `storage-provisioner-rancher`) | minikube |
| `quay.io/jetstack/cert-manager-controller`, `-cainjector`, `-webhook` | v1.21.2 | cert-manager (Flink operator webhook certificate) | `CERT_MANAGER_VERSION` |

## Check

```bash
kubectl --context cfk-local get pods -A -o json \
  | jq -r '.items[].spec | (.initContainers // [])[].image, .containers[].image' | sort -u
```

When changing a version, update this file in the same change (and [architecture.svg](architecture.svg) where versions are shown).
