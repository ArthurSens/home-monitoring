# Stupid simple setup to monitor my stuff at home.

## Main goals

* Monitor my stuff.
* Build some data to work with for my Prometheus and OpenTelemetry contributions.
* Experiment some other observability tools.

## The Stack so far

| Tool    | Function   |
|---------------|---------------------------|
| [Prometheus](https://github.com/prometheus/prometheus)    | Metrics collection   |
| [Loki](https://github.com/grafana/loki) | Logs collection |
| [Grafana](https://github.com/grafana/grafana)       | Data visualization        |
| [Alertmanager](https://github.com/prometheus/alertmanager)  | Alert management          |
| [Node-exporter](https://github.com/prometheus/node_exporter) | Notebook metrics exposure |
| [Blackbox-exporter](https://github.com/prometheus/blackbox_exporter) | Metrics about external HTTPS probing results |