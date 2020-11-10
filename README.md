# Stupid simple setup to monitor my stuff at home.

## Main goals

* Monitor my stuff.
* Build some data to work with for my Prometheus contributions.
* Experiment some other observability tools.

## The Stack so far

| Tool    | Function   |
|---------------|---------------------------|
| [Prometheus](https://github.com/prometheus/prometheus)    | Metrics collection   |
| [Loki](https://github.com/grafana/loki) | Logs collection |
| [Tempo](https://github.com/grafana/tempo) | Traces collection |
| [Grafana](https://github.com/grafana/grafana)       | Data visualization        |
| [Alertmanager](https://github.com/prometheus/alertmanager)  | Alert management          |
| [Telegrambot](https://github.com/metalmatze/alertmanager-bot)   | Alert routing to Telegram |
| [Node-exporter](https://github.com/prometheus/node_exporter) | Notebook metrics exposure |
| [Blackbox-exporter](https://github.com/prometheus/blackbox_exporter) | Metrics about external HTTPS probing results |
| [TimescaleDB](https://github.com/timescale/timescaledb) | Longterm storage, SQL based database for Prometheus metrics |
| [Promscale](https://github.com/timescale/promscale) | Connector between Prometheus <-> TimescaleDB |