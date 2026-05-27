# Agent Instructions

This repository is a Docker Compose based home observability lab. Its purpose is
to dogfood Grafana OSS projects locally while sending the same telemetry to
Grafana Cloud.

## Docker Compose Operations

- The local stack is managed with Docker Compose from the repo root.
- Before changing a service image tag for an experiment, verify whether the tag
  exists locally or in the expected registry.
- When testing a single service image, recreate only that service when possible:
  `docker compose up -d --no-deps <service>`.
- After service changes, verify with `docker compose ps`, targeted logs, and
  the relevant local endpoint or Prometheus query.
- Avoid publishing host ports unless host access is required. Prefer Docker DNS
  names for telemetry paths between services.

## Prometheus Rules

- Prometheus runs on host port `81` and has lifecycle reload enabled.
- For rule changes, validate with `promtool` before applying.
- Apply mounted rule/config changes by posting to the reload endpoint:
  `curl -fsS -X POST http://localhost:81/-/reload`.

## OpenTelemetry Collector

- The collector is a custom local distribution built from
  `opentelemetry-collector/builder-config.yaml`.
- Use the existing build targets for custom collector changes:
  `make otelcol-check` and `make otelcol-image`.
- For config-only collector changes, validate the config with the running image
  before relying on CI.

## Telemetry Identity Conventions

- Use `service.name` at the emitting service when the service supports it.
- Use `service.namespace=home-monitoring` for services in this stack.
- Use `deployment.environment=homelab` for local/home telemetry.
- Use `grafana.host.id=homelab` for Grafana Cloud Application Observability
  host identification from this Docker Compose environment.
- Do not encode namespaces into `service.name`; keep service names slash-free.

## Grafana Dashboards

- Dashboard JSON lives under `grafana/provisioning/dashboards/home/`.
- Prefer datasource variables over hard-coded datasource names or UIDs.
- Datasource variables should usually be hidden from the dashboard UI.
- Validate dashboard JSON with `gcx` CLI before pushing.
- Keep local dashboards and [Grafana Cloud Git Sync](https://grafana.com/docs/grafana/latest/as-code/observability-as-code/git-sync/) behavior in mind when changing
  dashboard JSON.

## Terraform And Grafana Cloud

- Grafana Cloud SLO, IRM, alerting, and related resources live under
  `terraform/grafana/`.
- Local Terraform state is intentionally local and gitignored.
- Do not expose or summarize token values from tfvars or environment files.
- When asked to apply Grafana Cloud changes, run Terraform from
  `terraform/grafana/` and verify the applied state with `gcx` when relevant.
- The expected Grafana Cloud `gcx` context is `arthursilvasens`.

## Local Verification

- Prefer the repo's existing verification scripts and Make targets over ad hoc
  checks.
- Use `scripts/verify-local-stack.sh` for end-to-end local stack verification
  when changes affect telemetry flow, dashboards, collector pipelines, or
  service identity.
- For narrow changes, run targeted validation first, such as:
  - `docker compose config --quiet`
  - collector config validation with `--feature-gates=service.profilesSupport`
  - `promtool check config` or `promtool check rules`
  - dashboard JSON validation

## GitHub, CI, And PRs

- Use `gh` for GitHub operations: reading PRs, checking CI, creating PRs, and
  enabling automerge.
- PRs target `master` unless the user says otherwise.
- When the user asks to open a PR, create a focused branch, commit only the
  relevant files, push, create the PR, and enable squash automerge if requested.
- If CI fails, inspect the failing check with `gh`, reproduce locally when
  possible, then push a focused fix.
- Do not push, commit, or enable automerge unless the user explicitly asks for
  that workflow.
