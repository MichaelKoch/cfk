# Isolated local cluster (cp-local)

The `cp-local` instance and its operators run in an isolated minikube cluster created by [local/cp-local-cluster.sh](../local/cp-local-cluster.sh). It never touches other minikube profiles; its context `cfk-local` is registered in `~/.kube/config` automatically, without switching the current context.

| Setting | Value |
|---|---|
| minikube profile | `cfk-local` (`PROFILE`) |
| kubeconfig | context `cfk-local` in `~/.kube/config` (added by `up`, removed by `delete`); the script and tests pin it with `--context` |
| Driver / runtime / Kubernetes | docker / containerd / v1.37.0 (`K8S_VERSION`) |
| Nodes | 1 × 6 CPU / 10 GiB (`CPUS`, `MEMORY_MB`) |
| Allocatable cap | kubelet `system-reserved` = host size − node size (docker nodes otherwise report the whole host) |
| Storage / cert-manager | `local-path` (addon `storage-provisioner-rancher`), cert-manager v1.21.2 |
| Operators values | [environments/operators-cp-local.yaml](../environments/operators-cp-local.yaml) |
| Instance values | [environments/cp-local.yaml](../environments/cp-local.yaml) |

## Prerequisites

`local/cp-local-cluster.sh check` verifies all of this (`up` and `all` run it first) and prints the versions found.

| Dependency | Tested | Needed for |
|---|---|---|
| [Docker Engine](https://docs.docker.com/engine/install/) | 29.4 (native in WSL 2 Debian) | minikube docker driver; `docker info` must work without sudo (user in group `docker`) |
| [minikube](https://minikube.sigs.k8s.io/docs/start/) | v1.39.0 | the cluster; must support Kubernetes v1.37 |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | v1.36 | everything (within one minor version of v1.37) |
| [Helm](https://helm.sh/docs/intro/install/) 3 | v3.20 | charts; `deploy` adds the repo `confluentinc` (`https://packages.confluent.io/helm`) if missing and builds the operators chart dependencies |
| `jq`, `curl` | jq 1.7, curl 8 | e2e tests, `flink`, `check` |
| Host (Docker/WSL VM) | 16 CPUs / 32 GiB | at least the node size, 6 CPUs / 10 GiB (`CPUS`, `MEMORY_MB`); about 2.4 CPUs / 6 GiB are requested at rest, the e2e Flink jobs add about 4 GiB |
| Disk | | 20 GB free under the Docker root (images take about 7.5 GB in the node) |
| Network | | Docker Hub (images), `packages.confluent.io` (charts), GitHub (cert-manager manifest) |
| Optional: VS Code extensions | Kubernetes, Confluent 2.3 | browse the cluster (context `cfk-local`), Kafka and Schema Registry ([import file](#external-access-and-vs-code-confluent-extension)) |

Fresh machine: install the tools, then run `local/cp-local-cluster.sh all` (the first run is the slowest: it pulls several GB of images). Smaller hosts can lower `CPUS`/`MEMORY_MB` (e.g. `CPUS=4 MEMORY_MB=8192`); below the requests above, pods stay `Pending`. NodePorts on the node IP are reachable from Linux and from WSL 2 with native Docker; with Docker Desktop the node IP is not reachable from the host, so use `kubectl port-forward` instead.

## Use

```bash
local/cp-local-cluster.sh check                 # prerequisites: tools, docker, host CPU/memory/disk
local/cp-local-cluster.sh all                   # check + up + deploy + both e2e tests
local/cp-local-cluster.sh up | deploy | test    # single steps
local/cp-local-cluster.sh ui                    # Control Center at http://localhost:9021 (port-forward)
local/cp-local-cluster.sh vscode                # write local/cp-local.vscode-confluent.json
local/cp-local-cluster.sh flink                 # shared Flink SQL registered in CMF (REST <node-ip>:30080)
local/cp-local-cluster.sh use                   # make cfk-local the current kubectl context
local/cp-local-cluster.sh stop | delete
```

The VS Code Kubernetes extension and other tools see the cluster as context `cfk-local`. Tests run against `CONTEXT` if set (the script sets it), otherwise the current context.

## External access and VS Code Confluent extension

`deploy` sets `platform.externalHost` to `minikube -p cfk-local ip` (docker on WSL/Linux: reachable from the host): Kafka bootstrap `<ip>:30000` (plaintext), Schema Registry `http://<ip>:30081`, CMF REST API `http://<ip>:30080/cmf/api/v1` (operators chart `cmfNodePort`). It also writes [local/cp-local.vscode-confluent.json](../local/cp-local.vscode-confluent.json) (generated, don't edit; `vscode` rewrites it). Import it in the Confluent extension: *Add New Connection → Import from file*. Enabling `externalHost` on a running instance needs `kubectl -n cp-local delete pod kafka-0`: CFK does not roll the broker, and the advertised address is set at pod start.

The first `deploy` pulls all images into the new node (several GB, including the ~900 MB `cp-flink-sql` 1.19 used by the SQL Gateway and CMF statements).

## Reduced footprint

CFK sets each JVM heap equal to the pod's memory request, so smaller requests lower real usage.

| Part | Chart default | cp-local |
|---|---|---|
| Kafka brokers | 3 × 250m / 1Gi | 1 × 250m / 768Mi, replication factor 1 (`kafka.configOverrides`) |
| KRaft controller | 250m / 768Mi | 100m / 512Mi |
| Schema Registry | 100m / 512Mi | 50m / 384Mi |
| SQL Gateway pod | 250m / 1Gi | 100m / 512Mi (limit 1Gi) |
| SQL Gateway session JM / TM | 1 CPU / 1024m, 1 CPU / 1536m | 0.5 CPU / 1024m, 0.5 CPU / 1536m |
| Flink operator / CMF | 500m / 1Gi, 250m / 1Gi | 100m / 512Mi, 100m / 768Mi (limits 1Gi) |
| Control Center (+ Prometheus, Alertmanager) | 250m / 1Gi, 5Gi + 5Gi volumes | 200m / 1Gi, 2Gi + 2Gi volumes |
| Shared compute pool, per statement | 1 / 1024m JM, 1 / 1536m TM, 2 slots | 0.25 / 768m JM, 0.5 / 1024m TM, 1 slot (two statements fit) |
| Connect, ksqlDB, REST Proxy, example FlinkApplication | on | off |

## Notes

- One broker means no fault tolerance; `kafka.configOverrides` sets every internal topic to replication factor 1. `controlCenter.configOverrides` does the same for the Control Center internal topics. Don't use these values with more than one broker.
