#!/usr/bin/env bash

set -Eeuo pipefail

COMPOSE=${COMPOSE:-"docker compose"}
START_STACK=1
TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-180}
FAILURE_DIAGNOSTICS_PRINTED=0

GRAFANA_URL=${GRAFANA_URL:-http://localhost:82}
GRAFANA_USER=${GRAFANA_USER:-admin}
GRAFANA_PASSWORD_FILE=${GRAFANA_PASSWORD_FILE:-secrets/grafana-admin-password}
PROMETHEUS_URL=${PROMETHEUS_URL:-http://localhost:81}
ALERTMANAGER_URL=${ALERTMANAGER_URL:-http://localhost:83}
LOKI_URL=${LOKI_URL:-http://localhost:3100}
TEMPO_URL=${TEMPO_URL:-http://localhost:3200}
PYROSCOPE_URL=${PYROSCOPE_URL:-http://localhost:4040}

EXPECTED_PROMETHEUS_JOBS=(
  home-monitoring/alertmanager
  home-monitoring/blackbox_exporter
  home-monitoring/garmin_exporter
  home-monitoring/grafana
  home-monitoring/loki
  home-monitoring/node_exporter
  home-monitoring/otel-collector
  home-monitoring/prometheus
  home-monitoring/pyroscope
  home-monitoring/tempo
)

EXPECTED_LOKI_LOG_SERVICES=(
  alertmanager
  blackbox_exporter
  garmin_exporter
  grafana
  loki
  node_exporter
  otel-collector
  prometheus
  pyroscope
  tempo
)

CI_QUIET_LOKI_LOG_SERVICES=(
  blackbox_exporter
  node_exporter
  prometheus
)

EXPECTED_PROFILE_RECEIVERS=(
  pprof/alertmanager
  pprof/blackbox_exporter
  pprof/garmin_exporter
  pprof/grafana
  pprof/loki
  pprof/node_exporter
  pprof/otel-collector
  pprof/prometheus
  pprof/pyroscope
  pprof/tempo
)

EXPECTED_PROFILE_SERVICES=(
  alertmanager
  blackbox_exporter
  grafana
  loki
  node_exporter
  otel-collector
  prometheus
  pyroscope
  tempo
)

# Services that may exit or restart when credentials are invalid (e.g. CI placeholders).
COMPOSE_RUNNING_OPTIONAL_SERVICES=(
  garmin_exporter
)

usage() {
  printf '%s\n' "Usage: $0 [--no-start] [--timeout SECONDS]"
  printf '%s\n' ""
  printf '%s\n' "Verifies that the local Docker Compose observability stack is healthy."
  printf '%s\n' ""
  printf '%s\n' "Options:"
  printf '%s\n' "  --no-start                 Do not run 'docker compose up -d' before checks."
  printf '%s\n' "  --timeout SECONDS          Timeout for service readiness and most telemetry checks. Default: ${TIMEOUT_SECONDS}."
  printf '%s\n' "  -h, --help                 Show this help text."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-start)
      START_STACK=0
      shift
      ;;
    --timeout)
      TIMEOUT_SECONDS=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

log() {
  printf '[verify] %s\n' "$*"
}

pass() {
  printf '[pass] %s\n' "$*"
}

diag() {
  printf '[diag] %s\n' "$*" >&2
}

fail() {
  printf '[fail] %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

run() {
  log "$*"
  "$@"
}

load_grafana_password() {
  if [[ -n "${GRAFANA_PASSWORD:-}" ]]; then
    return
  fi

  if [[ ! -f "$GRAFANA_PASSWORD_FILE" ]]; then
    fail "Missing Grafana admin password file: ${GRAFANA_PASSWORD_FILE}"
  fi

  GRAFANA_PASSWORD=$(<"$GRAFANA_PASSWORD_FILE")
  export GRAFANA_PASSWORD
}

wait_until() {
  local description=$1
  local timeout=$2
  shift 2

  local start now
  start=$(date +%s)

  until "$@" >/dev/null 2>&1; do
    now=$(date +%s)
    if (( now - start >= timeout )); then
      "$@" || true
      fail "${description} did not become healthy within ${timeout}s"
    fi
    sleep 3
  done

  pass "$description"
}

http_ready() {
  local url=$1
  curl -fsS -o /dev/null "$url"
}

prometheus_query() {
  local query=$1
  curl -fsS --get "${PROMETHEUS_URL}/api/v1/query" --data-urlencode "query=${query}"
}

prometheus_has_expected_jobs() {
  local response
  response=$(prometheus_query 'min by (job) (up)')

  RESPONSE="$response" EXPECTED_JOBS="${EXPECTED_PROMETHEUS_JOBS[*]}" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["RESPONSE"])
if payload.get("status") != "success":
    print("[diag] check=prometheus_expected_jobs status=query_failed", file=sys.stderr)
    print(f"[diag] response={json.dumps(payload, sort_keys=True)}", file=sys.stderr)
    sys.exit("Prometheus query did not succeed")

jobs = {
    item.get("metric", {}).get("job"): float(item.get("value", [0, "0"])[1])
    for item in payload["data"]["result"]
}
expected = set(os.environ["EXPECTED_JOBS"].split())
missing = sorted(expected - set(jobs))
if missing:
    observed = sorted(job for job in jobs if job)
    print("[diag] check=prometheus_expected_jobs status=missing_labels", file=sys.stderr)
    print("[diag] query=min by (job) (up)", file=sys.stderr)
    print(f"[diag] expected_jobs={json.dumps(sorted(expected))}", file=sys.stderr)
    print(f"[diag] observed_jobs={json.dumps(observed)}", file=sys.stderr)
    print(f"[diag] missing_jobs={json.dumps(missing)}", file=sys.stderr)
    sys.exit(f"Missing Prometheus jobs: {', '.join(missing)}")

down = sorted(job for job in expected if jobs[job] < 1)
if down:
    print("[diag] check=prometheus_expected_jobs status=down_targets", file=sys.stderr)
    print("[diag] query=min by (job) (up)", file=sys.stderr)
    print(f"[diag] down_jobs={json.dumps(down)}", file=sys.stderr)
    print(f"[diag] observed_values={json.dumps(jobs, sort_keys=True)}", file=sys.stderr)
    sys.exit(f"Prometheus jobs with down targets: {', '.join(down)}")
PY
}

prometheus_any_positive() {
  local query=$1
  local response
  response=$(prometheus_query "$query")

  RESPONSE="$response" QUERY="$query" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["RESPONSE"])
if payload.get("status") != "success":
    print("[diag] check=prometheus_any_positive status=query_failed", file=sys.stderr)
    print(f"[diag] query={os.environ['QUERY']}", file=sys.stderr)
    print(f"[diag] response={json.dumps(payload, sort_keys=True)}", file=sys.stderr)
    sys.exit("Prometheus query did not succeed")

result = payload["data"]["result"]
for item in result:
    if float(item["value"][1]) > 0:
        sys.exit(0)

print("[diag] check=prometheus_any_positive status=no_positive_series", file=sys.stderr)
print(f"[diag] query={os.environ['QUERY']}", file=sys.stderr)
print(f"[diag] series_count={len(result)}", file=sys.stderr)
for index, item in enumerate(result[:10]):
    print(f"[diag] series[{index}].labels={json.dumps(item.get('metric', {}), sort_keys=True)}", file=sys.stderr)
    print(f"[diag] series[{index}].value={item.get('value', [None, None])[1]}", file=sys.stderr)

sys.exit("No positive Prometheus series found")
PY
}

expected_loki_log_services() {
  if [[ "${CI:-}" != "true" ]]; then
    printf '%s\n' "${EXPECTED_LOKI_LOG_SERVICES[@]}"
    return
  fi

  comm -23 \
    <(printf '%s\n' "${EXPECTED_LOKI_LOG_SERVICES[@]}" | sort) \
    <(printf '%s\n' "${CI_QUIET_LOKI_LOG_SERVICES[@]}" | sort)
}

collector_has_single_log_receiver_per_container() {
  local query response
  query='sum by (receiver) (rate(otelcol_receiver_accepted_log_records_total{receiver=~"file_log/docker/receiver_creator.*"}[1m]))'
  response=$(prometheus_query "$query")

  RESPONSE="$response" QUERY="$query" python3 - <<'PY'
import collections
import json
import os
import re
import sys

payload = json.loads(os.environ["RESPONSE"])
if payload.get("status") != "success":
    print("[diag] check=collector_single_log_receiver_per_container status=query_failed", file=sys.stderr)
    print(f"[diag] query={os.environ['QUERY']}", file=sys.stderr)
    print(f"[diag] response={json.dumps(payload, sort_keys=True)}", file=sys.stderr)
    sys.exit("Prometheus query did not succeed")

container_receivers = collections.defaultdict(list)
for item in payload["data"]["result"]:
    if float(item.get("value", [0, "0"])[1]) <= 0:
        continue
    receiver = item.get("metric", {}).get("receiver", "")
    match = re.search(r"/([0-9a-f]{64})(?::\d+)?$", receiver)
    if match:
        container_receivers[match.group(1)].append(receiver)

duplicates = {
    container_id: sorted(receivers)
    for container_id, receivers in container_receivers.items()
    if len(receivers) > 1
}
if duplicates:
    print("[diag] check=collector_single_log_receiver_per_container status=duplicate_receivers", file=sys.stderr)
    print(f"[diag] query={os.environ['QUERY']}", file=sys.stderr)
    print(f"[diag] duplicate_receivers={json.dumps(duplicates, sort_keys=True)}", file=sys.stderr)
    sys.exit("Multiple Docker log receivers are ingesting from the same container")
PY
}

prometheus_has_expected_profile_receivers() {
  local response
  response=$(prometheus_query 'sum by (receiver) (otelcol_scraper_scraped_profile_records_total)')

  RESPONSE="$response" EXPECTED_RECEIVERS="${EXPECTED_PROFILE_RECEIVERS[*]}" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["RESPONSE"])
if payload.get("status") != "success":
    print("[diag] check=prometheus_expected_profile_receivers status=query_failed", file=sys.stderr)
    print(f"[diag] response={json.dumps(payload, sort_keys=True)}", file=sys.stderr)
    sys.exit("Prometheus query did not succeed")

receivers = {item.get("metric", {}).get("receiver") for item in payload["data"]["result"]}
expected = set(os.environ["EXPECTED_RECEIVERS"].split())
missing = sorted(expected - receivers)
if missing:
    observed = sorted(receiver for receiver in receivers if receiver)
    print("[diag] check=prometheus_expected_profile_receivers status=missing_labels", file=sys.stderr)
    print("[diag] query=sum by (receiver) (otelcol_scraper_scraped_profile_records_total)", file=sys.stderr)
    print(f"[diag] expected_receivers={json.dumps(sorted(expected))}", file=sys.stderr)
    print(f"[diag] observed_receivers={json.dumps(observed)}", file=sys.stderr)
    print(f"[diag] missing_receivers={json.dumps(missing)}", file=sys.stderr)
    sys.exit(f"Missing profile receivers: {', '.join(missing)}")
PY
}

pyroscope_has_expected_profile_services() {
  local now start request response
  now=$(date +%s)000
  start=$(( $(date +%s) - 3600 ))000
  request=$(printf '{"start":%s,"end":%s,"name":"service_name","matchers":[]}' "$start" "$now")
  response=$(curl -fsS \
    -H "Content-Type: application/json" \
    -d "$request" \
    "${PYROSCOPE_URL}/querier.v1.QuerierService/LabelValues")

  RESPONSE="$response" EXPECTED_SERVICES="${EXPECTED_PROFILE_SERVICES[*]}" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["RESPONSE"])
services = set(payload.get("names", []))
expected = set(os.environ["EXPECTED_SERVICES"].split())
missing = sorted(expected - services)
if missing:
    observed = sorted(service for service in services if service)
    print("[diag] check=pyroscope_expected_profile_services status=missing_labels", file=sys.stderr)
    print(f"[diag] expected_services={json.dumps(sorted(expected))}", file=sys.stderr)
    print(f"[diag] observed_services={json.dumps(observed)}", file=sys.stderr)
    print(f"[diag] missing_services={json.dumps(missing)}", file=sys.stderr)
    sys.exit(f"Missing profile services: {', '.join(missing)}")
PY
}

loki_has_recent_logs() {
  local response
  response=$(curl -fsS --get "${LOKI_URL}/loki/api/v1/query" \
    --data-urlencode 'query=sum(count_over_time({container_name=~".+"}[5m]))')

  RESPONSE="$response" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["RESPONSE"])
if payload.get("status") != "success":
    print("[diag] check=loki_recent_logs status=query_failed", file=sys.stderr)
    print(f"[diag] response={json.dumps(payload, sort_keys=True)}", file=sys.stderr)
    sys.exit("Loki query did not succeed")

result = payload["data"]["result"]
for item in result:
    if float(item["value"][1]) > 0:
        sys.exit(0)

print("[diag] check=loki_recent_logs status=no_positive_series", file=sys.stderr)
print('[diag] query=sum(count_over_time({container_name=~".+"}[5m]))', file=sys.stderr)
print(f"[diag] series_count={len(result)}", file=sys.stderr)
for index, item in enumerate(result[:10]):
    print(f"[diag] series[{index}].labels={json.dumps(item.get('metric', {}), sort_keys=True)}", file=sys.stderr)
    print(f"[diag] series[{index}].value={item.get('value', [None, None])[1]}", file=sys.stderr)

sys.exit("No recent Loki logs found")
PY
}

loki_has_app_o11y_service_logs() {
  local query response
  query='sum by (service_name, service_namespace, deployment_environment) (count_over_time({service_namespace="home-monitoring", deployment_environment="homelab", service_name=~"prometheus|grafana|otel-collector|loki|tempo|pyroscope|alertmanager|node_exporter|blackbox_exporter|garmin_exporter"}[5m]))'
  response=$(curl -fsS --get "${LOKI_URL}/loki/api/v1/query" \
    --data-urlencode "query=${query}")

  RESPONSE="$response" QUERY="$query" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["RESPONSE"])
if payload.get("status") != "success":
    print("[diag] check=loki_app_o11y_service_logs status=query_failed", file=sys.stderr)
    print(f"[diag] response={json.dumps(payload, sort_keys=True)}", file=sys.stderr)
    sys.exit("Loki query did not succeed")

result = payload["data"]["result"]
for item in result:
    metric = item.get("metric", {})
    if (
        float(item["value"][1]) > 0
        and metric.get("service_name")
        and metric.get("service_namespace") == "home-monitoring"
        and metric.get("deployment_environment") == "homelab"
    ):
        sys.exit(0)

print("[diag] check=loki_app_o11y_service_logs status=no_positive_series", file=sys.stderr)
print(f"[diag] query={os.environ['QUERY']}", file=sys.stderr)
print(f"[diag] series_count={len(result)}", file=sys.stderr)
for index, item in enumerate(result[:10]):
    print(f"[diag] series[{index}].labels={json.dumps(item.get('metric', {}), sort_keys=True)}", file=sys.stderr)
    print(f"[diag] series[{index}].value={item.get('value', [None, None])[1]}", file=sys.stderr)

sys.exit("No recent Loki logs with App O11y service identity found")
PY
}

loki_has_expected_service_logs() {
  local expected_services query response
  expected_services=$(expected_loki_log_services | paste -sd ' ' -)
  query='sum by (service_name) (count_over_time({service_namespace="home-monitoring", deployment_environment="homelab", service_name=~".+"}[30m]))'
  response=$(curl -fsS --get "${LOKI_URL}/loki/api/v1/query" \
    --data-urlencode "query=${query}")

  RESPONSE="$response" QUERY="$query" EXPECTED_SERVICES="$expected_services" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["RESPONSE"])
if payload.get("status") != "success":
    print("[diag] check=loki_expected_service_logs status=query_failed", file=sys.stderr)
    print(f"[diag] response={json.dumps(payload, sort_keys=True)}", file=sys.stderr)
    sys.exit("Loki query did not succeed")

services = {
    item.get("metric", {}).get("service_name")
    for item in payload["data"]["result"]
    if float(item.get("value", [0, "0"])[1]) > 0
}
expected = set(os.environ["EXPECTED_SERVICES"].split())
missing = sorted(expected - services)
if missing:
    observed = sorted(service for service in services if service)
    print("[diag] check=loki_expected_service_logs status=missing_services", file=sys.stderr)
    print(f"[diag] query={os.environ['QUERY']}", file=sys.stderr)
    print(f"[diag] expected_services={json.dumps(sorted(expected))}", file=sys.stderr)
    print(f"[diag] observed_services={json.dumps(observed)}", file=sys.stderr)
    print(f"[diag] missing_services={json.dumps(missing)}", file=sys.stderr)
    sys.exit(f"Missing Loki logs for services: {', '.join(missing)}")
PY
}

tempo_has_recent_traces() {
  local now start response
  now=$(date +%s)
  start=$((now - 900))
  response=$(curl -fsS "${TEMPO_URL}/api/search?start=${start}&end=${now}&limit=10")

  RESPONSE="$response" START="$start" END="$now" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["RESPONSE"])
if payload.get("traces"):
    sys.exit(0)

print("[diag] check=tempo_recent_traces status=no_traces", file=sys.stderr)
print(f"[diag] search_window_start={os.environ['START']}", file=sys.stderr)
print(f"[diag] search_window_end={os.environ['END']}", file=sys.stderr)
print(f"[diag] response={json.dumps(payload, sort_keys=True)}", file=sys.stderr)

sys.exit("No recent Tempo traces found")
PY
}

grafana_datasource_is_healthy() {
  local uid=$1
  local response
  response=$(curl -fsS -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" "${GRAFANA_URL}/api/datasources/uid/${uid}/health")

  RESPONSE="$response" DATASOURCE_UID="$uid" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["RESPONSE"])
if payload.get("status") == "OK":
    sys.exit(0)

print("[diag] check=grafana_datasource_health status=unhealthy", file=sys.stderr)
print(f"[diag] datasource_uid={os.environ['DATASOURCE_UID']}", file=sys.stderr)
print(f"[diag] response={json.dumps(payload, sort_keys=True)}", file=sys.stderr)

sys.exit(f"Datasource health check failed: {payload}")
PY
}

generate_activity() {
  curl -fsS -o /dev/null "${GRAFANA_URL}/api/health" || true
  curl -fsS -o /dev/null "${PROMETHEUS_URL}/-/ready" || true
  curl -fsS -o /dev/null "${ALERTMANAGER_URL}/-/ready" || true
  curl -fsS -o /dev/null "${LOKI_URL}/ready" || true
  curl -fsS -o /dev/null "${TEMPO_URL}/ready" || true
  curl -fsS -o /dev/null "${PYROSCOPE_URL}/ready" || true
}

check_running_services() {
  local expected running missing optional
  expected=$($COMPOSE config --services | sort)
  optional=$(printf '%s\n' "${COMPOSE_RUNNING_OPTIONAL_SERVICES[@]}" | sort)
  expected=$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$optional"))
  running=$($COMPOSE ps --status running --services | sort)
  missing=$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$running"))

  if [[ -n "$missing" ]]; then
    diag "check=compose_running_services status=missing_services"
    diag "missing_services=$(printf '%s' "$missing" | paste -sd ',' -)"
    diag "running_services=$(printf '%s' "$running" | paste -sd ',' -)"
    return 1
  fi
}

prepare_local_storage() {
  mkdir -p grafana/storage
  chmod 777 grafana/storage
}

print_failure_diagnostics() {
  if (( FAILURE_DIAGNOSTICS_PRINTED == 1 )); then
    return
  fi
  FAILURE_DIAGNOSTICS_PRINTED=1

  set +e
  diag "failure_diagnostics=begin"
  diag "compose_ps=begin"
  $COMPOSE ps >&2
  diag "compose_ps=end"

  diag "prometheus_jobs_query=begin"
  prometheus_query 'count by (job) (up)' >&2
  printf '\n' >&2
  diag "prometheus_jobs_query=end"

  diag "collector_exporter_metrics_query=begin"
  prometheus_query 'sum by (exporter) (rate(otelcol_exporter_sent_metric_points_total[5m]))' >&2
  printf '\n' >&2
  diag "collector_exporter_metrics_query=end"

  diag "collector_exporter_logs_query=begin"
  prometheus_query 'sum by (exporter) (rate(otelcol_exporter_sent_log_records_total[5m]))' >&2
  printf '\n' >&2
  diag "collector_exporter_logs_query=end"

  diag "collector_exporter_traces_query=begin"
  prometheus_query 'sum by (exporter) (rate(otelcol_exporter_sent_spans_total[5m]))' >&2
  printf '\n' >&2
  diag "collector_exporter_traces_query=end"

  diag "otel_collector_logs=begin"
  $COMPOSE logs --no-color --tail=120 otel-collector >&2
  diag "otel_collector_logs=end"
  diag "failure_diagnostics=end"
}

on_exit() {
  local status=$?
  if (( status != 0 )); then
    print_failure_diagnostics
  fi
}

trap on_exit EXIT

need_cmd docker
need_cmd curl
need_cmd python3

load_grafana_password

run $COMPOSE config --quiet

if (( START_STACK == 1 )); then
  prepare_local_storage
  run $COMPOSE up -d
fi

wait_until "all Compose services are running" "$TIMEOUT_SECONDS" check_running_services

generate_activity

wait_until "Grafana is ready" "$TIMEOUT_SECONDS" http_ready "${GRAFANA_URL}/api/health"
wait_until "Prometheus is ready" "$TIMEOUT_SECONDS" http_ready "${PROMETHEUS_URL}/-/ready"
wait_until "Alertmanager is ready" "$TIMEOUT_SECONDS" http_ready "${ALERTMANAGER_URL}/-/ready"
wait_until "Loki is ready" "$TIMEOUT_SECONDS" http_ready "${LOKI_URL}/ready"
wait_until "Tempo is ready" "$TIMEOUT_SECONDS" http_ready "${TEMPO_URL}/ready"
wait_until "Pyroscope is ready" "$TIMEOUT_SECONDS" http_ready "${PYROSCOPE_URL}/ready"

generate_activity

wait_until "Prometheus has all expected collector-scraped jobs up" "$TIMEOUT_SECONDS" prometheus_has_expected_jobs
wait_until "Loki has recent stack logs" "$TIMEOUT_SECONDS" loki_has_recent_logs
wait_until "Loki logs have App O11y service identity" "$TIMEOUT_SECONDS" loki_has_app_o11y_service_logs
wait_until "Loki has logs from all expected services" "$TIMEOUT_SECONDS" loki_has_expected_service_logs
wait_until "Tempo has recent traces" "$TIMEOUT_SECONDS" tempo_has_recent_traces
wait_until "Grafana can query the Prometheus datasource" "$TIMEOUT_SECONDS" grafana_datasource_is_healthy prometheus
wait_until "Grafana can query the Loki datasource" "$TIMEOUT_SECONDS" grafana_datasource_is_healthy loki
wait_until "Grafana can query the Tempo datasource" "$TIMEOUT_SECONDS" grafana_datasource_is_healthy tempo
wait_until "Grafana can query the Pyroscope datasource" "$TIMEOUT_SECONDS" grafana_datasource_is_healthy pyroscope

wait_until "collector exports metrics to local Prometheus" "$TIMEOUT_SECONDS" \
  prometheus_any_positive 'sum(rate(otelcol_exporter_sent_metric_points_total{exporter="otlp_http/prometheus"}[5m]))'
wait_until "collector exports logs to local Loki" "$TIMEOUT_SECONDS" \
  prometheus_any_positive 'sum(rate(otelcol_exporter_sent_log_records_total{exporter="otlp_http/loki"}[5m]))'
wait_until "collector has at most one Docker log receiver per container" "$TIMEOUT_SECONDS" \
  collector_has_single_log_receiver_per_container
wait_until "collector exports traces to local Tempo" "$TIMEOUT_SECONDS" \
  prometheus_any_positive 'sum(rate(otelcol_exporter_sent_spans_total{exporter="otlp_http/tempo"}[5m]))'
wait_until "collector exports profiles to local Pyroscope" "$TIMEOUT_SECONDS" \
  prometheus_any_positive 'sum(rate(otelcol_exporter_sent_profile_samples_total{exporter="otlp_http/pyroscope"}[5m]))'
wait_until "collector scrapes profiles from all expected services" "$TIMEOUT_SECONDS" \
  prometheus_has_expected_profile_receivers
wait_until "Pyroscope has profiles from all expected services" "$TIMEOUT_SECONDS" \
  pyroscope_has_expected_profile_services

pass "local stack verification completed"
