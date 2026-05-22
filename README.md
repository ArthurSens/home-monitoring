# Home Monitoring

This repository is my home observability lab. The goal is to dogfood Grafana open source projects locally while also sending the same telemetry to Grafana Cloud.

It is intentionally small enough to run with Docker Compose, but complete enough to exercise metrics, logs, traces, profiles, dashboards, alerting, and OpenTelemetry Collector pipelines end to end.

## Goals

- Monitor my local machine and a few external endpoints.
- Dogfood Grafana OSS projects: Grafana, Loki, Tempo, Pyroscope, and related dashboards.
- Dogfood Grafana Cloud ingestion for metrics, logs, traces, and profiles through OTLP.
- Keep dashboards versioned in Git and sync them with Grafana Cloud using Grafana Git Sync.
- Generate realistic telemetry for Prometheus, OpenTelemetry, and Grafana contributions.

## Stack

| Component | Purpose |
| --- | --- |
| [Grafana](https://github.com/grafana/grafana) | Local visualization, dashboards, drilldowns, and datasource provisioning. |
| [Prometheus](https://github.com/prometheus/prometheus) | Local metrics backend. It receives metrics from the collector through OTLP. |
| [Loki](https://github.com/grafana/loki) | Local logs backend. It receives logs from the collector through OTLP. |
| [Tempo](https://github.com/grafana/tempo) | Local traces backend. It receives traces from the collector through OTLP. |
| [Pyroscope](https://github.com/grafana/pyroscope) | Local profiles backend. It receives profiles from the collector through OTLP. |
| [OpenTelemetry Collector](https://github.com/open-telemetry/opentelemetry-collector) | Custom local distribution for the central telemetry pipeline for metrics, logs, traces, and profiles. |
| [Alertmanager](https://github.com/prometheus/alertmanager) | Alert routing and tracing target. |
| [Node Exporter](https://github.com/prometheus/node_exporter) | Host metrics. |
| [Blackbox Exporter](https://github.com/prometheus/blackbox_exporter) | External endpoint probing. |
| [Garmin Exporter](https://github.com/barnes-c/garmin_exporter) | Garmin Connect health and training metrics (scraped every 5m). |
| Grafana Cloud | Remote metrics, logs, traces, and profiles for cloud dogfooding. |

## Custom Collector

The `otel-collector` Compose service builds a minimal OpenTelemetry Collector distribution from `opentelemetry-collector/builder-config.yaml`.

Useful commands:

```sh
make otelcol-check
make otelcol-image
```

## Grafana Cloud Git Sync

Use [Grafana Git Sync](https://grafana.com/docs/grafana-cloud/as-code/observability-as-code/git-sync/) to keep dashboard JSON in this repository synced with Grafana Cloud.
