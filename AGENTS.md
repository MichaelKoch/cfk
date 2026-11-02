# AGENTS.md

Shared instructions for AI coding agents (Claude Code, GitHub Copilot, and others) working in this repository. This file is the single source of truth; tool-specific files (`CLAUDE.md`, `.github/copilot-instructions.md`) only point here.

## Project overview

See [README.md](README.md) for what this project is, how to install it, and how to use it. Read it before making changes.

## Repository layout

- `charts/confluent-operators/` – operators chart (CFK, Flink operator, CMF), installed once into `confluent-operator`; creates and watches the instance namespaces
- `charts/confluent-platform/` – one Confluent Platform instance per namespace (CP custom resources, Flink environment, SQL Gateway); no operators
- `environments/` – per-instance values (`<namespace>.yaml`); `operators-cp-local.yaml` for the operators
- `local/` – isolated local minikube cluster (`cp-local-cluster.sh`): create, deploy, test, delete
- `doc/` – compact feature documentation, including the architecture diagram (`doc/architecture.svg`)
- `tests/` – end-to-end tests against the deployed cluster (`tests/flink-e2e/`, `tests/sql-gateway-e2e/`)

## Setup

Prerequisites (tools, versions, host size) are listed in [doc/local-cluster.md](doc/local-cluster.md#prerequisites); `local/cp-local-cluster.sh check` verifies them. `deploy` adds the Helm repo itself; for `helm lint`/`helm template` without the script:

```bash
helm repo add confluentinc https://packages.confluent.io/helm
helm dependency build charts/confluent-operators
```

Keep the prerequisites table, `check`, and the script in sync when adding a dependency (tool, image registry, chart repo, manifest URL). Every container image and version change updates [doc/images.md](doc/images.md).

## Build, test, and lint

```bash
helm lint charts/confluent-operators charts/confluent-platform                    # lint
helm template cp-local charts/confluent-platform -n cp-local -f environments/cp-local.yaml # render
local/cp-local-cluster.sh check                                                      # prerequisites: tools, docker, host CPU/memory/disk
local/cp-local-cluster.sh all                                                        # isolated minikube profile cfk-local: cluster + operators + cp-local + both e2e tests
local/cp-local-cluster.sh up | deploy | test | stop | delete                         # single steps
local/cp-local-cluster.sh ui | vscode | flink                                        # Control Center port-forward | VS Code Confluent connection file | CMF registration
local/cp-local-cluster.sh use                                                        # current kubectl context = cfk-local (registered in ~/.kube/config)
kubectl get confluent -n cp-local                                                    # verify
NS=cp-local tests/flink-e2e/run.sh                                                   # Flink SQL e2e test via CMF (Kafka -> Flink -> Kafka)
NS=cp-local tests/sql-gateway-e2e/run.sh                                             # Flink SQL Gateway e2e test (REST -> session cluster -> Kafka)
```

## Code style and conventions

- Match the style, naming, and idioms of the surrounding code.
- Keep changes focused; don't refactor unrelated code.
- Add or update tests alongside behavior changes.

## Documentation

- Always document features as compact Markdown files in the `doc/` folder (one file per feature or topic, short and to the point).
- No drift between features and docs: every change that adds, changes, or removes a feature updates the matching file in `doc/` in the same change. A feature change without a matching doc update is incomplete.
- The architecture diagram [doc/architecture.svg](doc/architecture.svg) (described in [doc/architecture.md](doc/architecture.md)) must always match the charts and `environments/`. No drift allowed: any change to components, namespaces/instances, per-environment toggles, versions, ports, or connections between components updates the SVG (and `architecture.md` if its table is affected) in the same change. Keep it a hand-written landscape SVG, check it renders without overlapping text, and treat a change that leaves the diagram stale as incomplete.

## Git and pull requests

- Don't commit or push unless asked.
- Use clear, imperative commit messages.
- Run tests and lint before proposing a PR.

## Things to avoid

- Never commit secrets, credentials, or `.env` files.
- Don't edit generated files by hand.
