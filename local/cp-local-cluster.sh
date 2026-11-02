#!/usr/bin/env bash
# Isolated local cluster for the cp-local instance: its own minikube profile (docker driver), registered
# as context cfk-local in ~/.kube/config without switching the current context. All kubectl/helm calls
# here pin that context. Mirrors the reference minikube setup (docker, containerd, Kubernetes v1.37.0,
# local-path storage, cert-manager, allocatable capped via kubelet system-reserved) on one small node.
#
#   local/cp-local-cluster.sh check    verify prerequisites: tools, docker daemon, host CPU/memory/disk
#   local/cp-local-cluster.sh up       check + create/start the cluster, storage and cert-manager
#   local/cp-local-cluster.sh deploy   add the Confluent Helm repo if missing, install operators and cp-local, wait until ready
#   local/cp-local-cluster.sh test     run both e2e tests against cp-local
#   local/cp-local-cluster.sh all      up + deploy + test (fresh machine: this is the only command needed)
#   local/cp-local-cluster.sh vscode   write local/cp-local.vscode-confluent.json (VS Code Confluent extension import)
#   local/cp-local-cluster.sh flink    show the shared Flink SQL setup registered in CMF (REST at <node-ip>:30080)
#   local/cp-local-cluster.sh ui       Control Center at http://localhost:9021 (port-forward, Ctrl+C to stop)
#   local/cp-local-cluster.sh use      make cfk-local the current kubectl context
#   local/cp-local-cluster.sh stop     stop the cluster (keeps data)
#   local/cp-local-cluster.sh delete   delete the cluster and its context
#
# Overrides (env): PROFILE, CPUS, MEMORY_MB, K8S_VERSION. Prerequisites: doc/local-cluster.md#prerequisites
set -euo pipefail

PROFILE=${PROFILE:-cfk-local}
CPUS=${CPUS:-6}
MEMORY_MB=${MEMORY_MB:-10240}
K8S_VERSION=${K8S_VERSION:-v1.37.0}
CERT_MANAGER_VERSION=v1.21.2
NS=cp-local
CONFLUENT_HELM_REPO=https://packages.confluent.io/helm
MIN_FREE_DISK_GB=20 # images (~7.5 GB in the node) + volumes + headroom
ROOT=$(cd "$(dirname "$0")/.." && pwd)
kubectl() { command kubectl --context "$PROFILE" "$@"; }
helm() { command helm --kube-context "$PROFILE" "$@"; }
die() { echo "error: $*" >&2; exit 1; }

# Prerequisites: tools on PATH, a reachable docker daemon, a host big enough for the node, free disk
check() {
  local t missing=() host_cpus host_mem_mb free_gb
  for t in docker minikube kubectl helm jq curl; do command -v "$t" >/dev/null || missing+=("$t"); done
  ((${#missing[@]} == 0)) || die "missing tools: ${missing[*]} (see doc/local-cluster.md#prerequisites)"
  docker info >/dev/null 2>&1 || die "docker daemon not reachable: start it and make sure your user can run 'docker info' without sudo"
  [[ $(command helm version --template '{{.Version}}') == v3.* ]] || echo "warning: tested with Helm 3, found $(command helm version --short)"
  # docker-driver nodes see the host; the node size must fit into it (kubelet system-reserved = host - node)
  host_cpus=$(docker info -f '{{.NCPU}}')
  host_mem_mb=$(($(docker info -f '{{.MemTotal}}') / 1048576))
  ((host_cpus >= CPUS)) || die "docker host has $host_cpus CPUs, the node needs CPUS=$CPUS (lower CPUS or give Docker/WSL more CPUs)"
  ((host_mem_mb >= MEMORY_MB)) || die "docker host has $host_mem_mb MiB, the node needs MEMORY_MB=$MEMORY_MB (lower MEMORY_MB or give Docker/WSL more memory)"
  free_gb=$(df -Pk "$(docker info -f '{{.DockerRootDir}}')" 2>/dev/null | awk 'NR == 2 { print int($4 / 1048576) }' || true)
  ((${free_gb:-0} >= MIN_FREE_DISK_GB)) || echo "warning: ${free_gb:-unknown} GB free for docker, about $MIN_FREE_DISK_GB GB recommended"
  echo "ok: docker $(docker version -f '{{.Server.Version}}'), $(minikube version --short), kubectl $(command kubectl version --client -o json | jq -r .clientVersion.gitVersion), helm $(command helm version --template '{{.Version}}'), $(jq --version)"
  echo "ok: host $host_cpus CPUs / $host_mem_mb MiB / ${free_gb:-?} GB free disk, node $CPUS CPUs / $MEMORY_MB MiB"
}

up() {
  check
  # docker-driver nodes report the host's CPU and memory; reserve the rest so the scheduler sees only CPUS/MEMORY_MB
  local host_cpus host_mem_mb
  host_cpus=$(docker info -f '{{.NCPU}}')
  host_mem_mb=$(($(docker info -f '{{.MemTotal}}') / 1048576))
  minikube start -p "$PROFILE" --driver=docker --container-runtime=containerd --kubernetes-version="$K8S_VERSION" \
    --keep-context --nodes=1 --cpus="$CPUS" --memory="${MEMORY_MB}mb" \
    --extra-config=kubelet.system-reserved="cpu=$(((host_cpus - CPUS) * 1000))m,memory=$((host_mem_mb - MEMORY_MB))Mi"
  minikube -p "$PROFILE" addons enable storage-provisioner-rancher
  kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/$CERT_MANAGER_VERSION/cert-manager.yaml" >/dev/null
  kubectl -n cert-manager wait --for=condition=Available deploy --all --timeout=300s
}

deploy() {
  minikube -p "$PROFILE" status >/dev/null 2>&1 || die "cluster $PROFILE is not running: run 'local/cp-local-cluster.sh up' first"
  command helm repo list -o json 2>/dev/null | jq -e --arg u "$CONFLUENT_HELM_REPO" 'any(.[]; .url == $u)' >/dev/null ||
    command helm repo add confluentinc "$CONFLUENT_HELM_REPO" >/dev/null
  helm dependency build "$ROOT/charts/confluent-operators" >/dev/null
  helm upgrade --install confluent-operators "$ROOT/charts/confluent-operators" -n confluent-operator --create-namespace \
    -f "$ROOT/environments/operators-cp-local.yaml" --wait --timeout 10m
  helm upgrade --install cp-local "$ROOT/charts/confluent-platform" -n "$NS" -f "$ROOT/environments/$NS.yaml" \
    --set platform.externalHost="$(minikube -p "$PROFILE" ip)"
  echo "waiting for cp-local (first run pulls all images)"
  kubectl -n "$NS" wait --for=jsonpath='{.status.phase}'=RUNNING kraftcontroller/kraftcontroller kafka/kafka schemaregistry/schemaregistry --timeout=15m
  kubectl -n "$NS" wait --for=condition=Available deploy/sql-gateway --timeout=10m
  kubectl -n "$NS" wait --for=jsonpath='{.status.phase}'=RUNNING controlcenter/controlcenter --timeout=15m
  kubectl -n "$NS" wait --for=jsonpath='{.status.cfkInternalState}'=CREATED flinkenvironment/"$NS" \
    flinkkafkacatalog/"$NS" flinkkafkadatabase/kafka flinkcomputepool/shared --timeout=5m
  kubectl get confluent -n "$NS"
  vscode_connection
}

# Shared Flink SQL as registered in CMF, read from the CMF REST API NodePort
flink_info() {
  local cmf=http://$(minikube -p "$PROFILE" ip):30080/cmf/api/v1
  echo "CMF REST API: $cmf"
  echo "environments: $(curl -sf "$cmf/environments" | jq -c '[.items[].name]')"
  echo "compute pools ($NS): $(curl -sf "$cmf/environments/$NS/compute-pools" | jq -c '[.items[].metadata.name]')"
  echo "catalogs: $(curl -sf "$cmf/catalogs/kafka" | jq -c '[.items[].metadata.name]')"
  echo "databases ($NS): $(curl -sf "$cmf/catalogs/kafka/$NS/databases" | jq -c '[.items[].metadata.name]')"
  echo "statements ($NS): $(curl -sf "$cmf/environments/$NS/statements" | jq -c '[.items[] | {name: .metadata.name, phase: .status.phase}]')"
}

# Direct connection for the VS Code Confluent extension: Kafka and Schema Registry via NodePorts on the node IP.
# ssl.enabled must be explicit: the import form enables TLS for non-localhost brokers by default.
vscode_connection() {
  local ip file=$ROOT/local/cp-local.vscode-confluent.json
  ip=$(minikube -p "$PROFILE" ip)
  cat >"$file" <<EOF
{
  "name": "cp-local ($PROFILE)",
  "type": "DIRECT",
  "formConnectionType": "Confluent Platform",
  "kafka_cluster": { "bootstrap_servers": "$ip:30000", "ssl": { "enabled": false } },
  "schema_registry": { "uri": "http://$ip:30081", "ssl": { "enabled": false } }
}
EOF
  echo "VS Code Confluent extension: Add connection > Import from file > $file"
}

run_tests() {
  NS=$NS CONTEXT=$PROFILE "$ROOT/tests/sql-gateway-e2e/run.sh"
  NS=$NS CONTEXT=$PROFILE "$ROOT/tests/flink-e2e/run.sh"
}

case ${1:-} in
  check) check ;;
  up) up ;;
  deploy) deploy ;;
  test) run_tests ;;
  all) up && deploy && run_tests ;;
  vscode) vscode_connection ;;
  flink) flink_info ;;
  ui) kubectl -n "$NS" port-forward svc/controlcenter 9021:9021 ;;
  use) command kubectl config use-context "$PROFILE" ;;
  stop) minikube stop -p "$PROFILE" ;;
  delete) minikube delete -p "$PROFILE" ;;
  *) sed -n '2,/^set -euo/{/^#/p}' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
