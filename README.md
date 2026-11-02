# cfk

Set up and operate Confluent Platform on Kubernetes using Confluent for Kubernetes (CFK).

## Goal

This repository contains everything needed to deploy the Confluent for Kubernetes operator and run Confluent Platform on a Kubernetes cluster, following the official guide:
[Deploy Confluent for Kubernetes](https://docs.confluent.io/operator/current/co-deploy-operator.html).

It covers:

- **Setup:** deploying the CFK operator and the Confluent Platform components on Kubernetes.
- **Operations:** running, configuring, and maintaining Confluent Platform on Kubernetes.

## Getting started

### Prerequisites

- Docker Engine, `minikube`, `kubectl`, Helm 3, `jq` and `curl`
- A Docker host with at least 6 CPUs, 10 GiB RAM and 20 GB free disk, plus internet access (Docker Hub, `packages.confluent.io`, GitHub)

Versions, install links and sizing: [doc/local-cluster.md#prerequisites](doc/local-cluster.md#prerequisites). `local/cp-local-cluster.sh check` verifies them.

### Layout

| Namespace | Chart | Content |
|---|---|---|
| `confluent-operator` | `charts/confluent-operators` (once) | CFK operator, Flink operator, CMF |
| `cp-local` | `charts/confluent-platform` (values in `environments/cp-local.yaml`) | KRaft, Kafka (1 broker), Schema Registry, Control Center, Flink environment, SQL Gateway |

Both run in an isolated minikube cluster (profile `cfk-local`, context `cfk-local` in `~/.kube/config`), see [doc/local-cluster.md](doc/local-cluster.md). Connect, ksqlDB and REST Proxy are in the chart but off in `cp-local`.

### Installation

```bash
local/cp-local-cluster.sh check    # prerequisites
local/cp-local-cluster.sh all      # cluster + operators + cp-local + e2e tests (first run pulls several GB of images)
local/cp-local-cluster.sh use      # make cfk-local the current kubectl context
```

`all` is `up` (minikube profile `cfk-local`, `local-path` storage, cert-manager) + `deploy` (adds the Confluent Helm repo if missing, installs the operators and `cp-local`) + `test`; each step can also run alone.

### Usage

```bash
kubectl get confluent -n cp-local                              # component status
kubectl get flinkapplication,flinkdeployment -n cp-local        # Flink jobs
kubectl port-forward -n cp-local svc/sql-gateway 8083:8083      # Flink SQL Gateway REST
local/cp-local-cluster.sh ui                                    # Control Center at http://localhost:9021
local/cp-local-cluster.sh flink                                 # shared Flink SQL in CMF: catalog cp-local, database kafka, pool shared
local/cp-local-cluster.sh vscode                                # VS Code Confluent extension connection file (Kafka <node-ip>:30000, SR :30081)
local/cp-local-cluster.sh test                                  # both e2e tests
```

Details: [architecture](doc/architecture.md), [local test cluster](doc/local-cluster.md), [operators](doc/confluent-operators-chart.md), [platform instances](doc/confluent-platform-chart.md), [Flink](doc/flink.md), [SQL Gateway](doc/sql-gateway.md), [images and versions](doc/images.md).

## Development

See [AGENTS.md](AGENTS.md) for build, test, and lint commands and the coding conventions used in this repository.

## Contributing

<!-- How to propose changes, branch naming, review process. -->

## License

<!-- License information. -->
