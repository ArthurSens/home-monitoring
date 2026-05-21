#!/usr/bin/env bash

set -Eeuo pipefail

COMPOSE=${COMPOSE:-"docker compose"}
START_STACK=1
TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-180}

GRAFANA_URL=${GRAFANA_URL:-http://localhost:82}
PROMETHEUS_URL=${PROMETHEUS_URL:-http://localhost:81}
ALERTMANAGER_URL=${ALERTMANAGER_URL:-http://localhost:83}
LOKI_URL=${LOKI_URL:-http://localhost:3100}
TEMPO_URL=${TEMPO_URL:-http://localhost:3200}
PYROSCOPE_URL=${PYROSCOPE_URL:-http://localhost:4040}

EXPECTED_PROMETHEUS_JOBS=(
  alertmanager
  blackbox
  grafana
  loki
  node_exporter
  otelcol-contrib
  prometheus
  pyroscope
  tempo
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
  response=$(prometheus_query 'count by (job) (up)')

  RESPONSE="$response" EXPECTED_JOBS="${EXPECTED_PROMETHEUS_JOBS[*]}" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["RESPONSE"])
if payload.get("status") != "success":
    sys.exit("Prometheus query did not succeed")

jobs = {item.get("metric", {}).get("job") for item in payload["data"]["result"]}
expected = set(os.environ["EXPECTED_JOBS"].split())
missing = sorted(expected - jobs)
if missing:
    sys.exit(f"Missing Prometheus jobs: {', '.join(missing)}")
PY
}

prometheus_any_positive() {
  local query=$1
  local response
  response=$(prometheus_query "$query")

  RESPONSE="$response" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["RESPONSE"])
if payload.get("status") != "success":
    sys.exit("Prometheus query did not succeed")

for item in payload["data"]["result"]:
    if float(item["value"][1]) > 0:
        sys.exit(0)

sys.exit("No positive Prometheus series found")
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
    sys.exit("Loki query did not succeed")

for item in payload["data"]["result"]:
    if float(item["value"][1]) > 0:
        sys.exit(0)

sys.exit("No recent Loki logs found")
PY
}

tempo_has_recent_traces() {
  local now start response
  now=$(date +%s)
  start=$((now - 900))
  response=$(curl -fsS "${TEMPO_URL}/api/search?start=${start}&end=${now}&limit=10")

  RESPONSE="$response" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["RESPONSE"])
if payload.get("traces"):
    sys.exit(0)

sys.exit("No recent Tempo traces found")
PY
}

grafana_datasource_is_healthy() {
  local uid=$1
  local response
  response=$(curl -fsS -u admin:admin "${GRAFANA_URL}/api/datasources/uid/${uid}/health")

  RESPONSE="$response" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["RESPONSE"])
if payload.get("status") == "OK":
    sys.exit(0)

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
  local expected running missing
  expected=$($COMPOSE config --services | sort)
  running=$($COMPOSE ps --status running --services | sort)
  missing=$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$running"))

  if [[ -n "$missing" ]]; then
    printf 'Services not running:\n%s\n' "$missing" >&2
    return 1
  fi
}

need_cmd docker
need_cmd curl
need_cmd python3

run $COMPOSE config --quiet

if (( START_STACK == 1 )); then
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

wait_until "Prometheus has all expected collector-scraped jobs" "$TIMEOUT_SECONDS" prometheus_has_expected_jobs
wait_until "Loki has recent stack logs" "$TIMEOUT_SECONDS" loki_has_recent_logs
wait_until "Tempo has recent traces" "$TIMEOUT_SECONDS" tempo_has_recent_traces
wait_until "Grafana can query the Prometheus datasource" "$TIMEOUT_SECONDS" grafana_datasource_is_healthy prometheus
wait_until "Grafana can query the Loki datasource" "$TIMEOUT_SECONDS" grafana_datasource_is_healthy loki
wait_until "Grafana can query the Tempo datasource" "$TIMEOUT_SECONDS" grafana_datasource_is_healthy tempo
wait_until "Grafana can query the Pyroscope datasource" "$TIMEOUT_SECONDS" grafana_datasource_is_healthy pyroscope

wait_until "collector exports metrics to local Prometheus" "$TIMEOUT_SECONDS" \
  prometheus_any_positive 'sum(rate(otelcol_exporter_sent_metric_points_total{exporter="otlp_http/prometheus"}[5m]))'
wait_until "collector exports logs to local Loki" "$TIMEOUT_SECONDS" \
  prometheus_any_positive 'sum(rate(otelcol_exporter_sent_log_records_total{exporter="otlp_http/loki"}[5m]))'
wait_until "collector exports traces to local Tempo" "$TIMEOUT_SECONDS" \
  prometheus_any_positive 'sum(rate(otelcol_exporter_sent_spans_total{exporter="otlp_http/tempo"}[5m]))'
wait_until "collector exports profiles to local Pyroscope" "$TIMEOUT_SECONDS" \
  prometheus_any_positive 'sum(rate(otelcol_exporter_sent_profile_samples_total{exporter="otlp_http/pyroscope"}[5m]))'

pass "local stack verification completed"
