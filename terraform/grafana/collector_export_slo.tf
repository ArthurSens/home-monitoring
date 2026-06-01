locals {
  collector_export_slos = {
    metrics = {
      display_name = "metric"
      metric_name  = "metric_points"
    }
    traces = {
      display_name = "trace"
      metric_name  = "spans"
    }
    profiles = {
      display_name = "profile"
      metric_name  = "profiles"
    }
    logs = {
      display_name = "log"
      metric_name  = "log_records"
    }
  }
}

resource "grafana_slo" "collector_export" {
  for_each = local.collector_export_slos

  name        = "Collector ${each.value.display_name} export reliability"
  description = "Tracks the fraction of ${each.value.display_name} telemetry items exported successfully by the home-monitoring collector."

  query {
    type = "freeform"

    freeform {
      query = <<-PROMQL
        (
          (
            sum(rate(otelcol_exporter_sent_${each.value.metric_name}_total{data_type="${each.key}"}[$__rate_interval]))
            /
            (
              sum(rate(otelcol_exporter_sent_${each.value.metric_name}_total{data_type="${each.key}"}[$__rate_interval]))
              + (sum(rate(otelcol_exporter_send_failed_${each.value.metric_name}_total{data_type="${each.key}"}[$__rate_interval])) or vector(0))
              + (sum(rate(otelcol_exporter_enqueue_failed_${each.value.metric_name}_total{data_type="${each.key}"}[$__rate_interval])) or vector(0))
            )
          )
          unless
          (
            (
              sum(rate(otelcol_exporter_sent_${each.value.metric_name}_total{data_type="${each.key}"}[$__rate_interval]))
              + (sum(rate(otelcol_exporter_send_failed_${each.value.metric_name}_total{data_type="${each.key}"}[$__rate_interval])) or vector(0))
              + (sum(rate(otelcol_exporter_enqueue_failed_${each.value.metric_name}_total{data_type="${each.key}"}[$__rate_interval])) or vector(0))
            ) == 0
          )
        )
        or vector(1)
      PROMQL
    }
  }

  objectives {
    value  = var.collector_export_slo_objective
    window = var.collector_export_slo_window
  }

  destination_datasource {
    uid = var.prometheus_datasource_uid
  }

  label {
    key   = "service"
    value = "otel-collector"
  }

  label {
    key   = "signal"
    value = each.key
  }

  label {
    key   = "team"
    value = "homelab-operations"
  }

  alerting {
    fastburn {
      annotation {
        key   = "name"
        value = "Collector ${each.value.display_name} export SLO fast burn"
      }

      annotation {
        key   = "description"
        value = "Collector ${each.value.display_name} export failures are burning the homelab operations SLO error budget quickly."
      }

      label {
        key   = "service"
        value = "otel-collector"
      }

      label {
        key   = "signal"
        value = each.key
      }

      label {
        key   = "team"
        value = "homelab-operations"
      }
    }

    slowburn {
      annotation {
        key   = "name"
        value = "Collector ${each.value.display_name} export SLO slow burn"
      }

      annotation {
        key   = "description"
        value = "Collector ${each.value.display_name} export failures are gradually burning the homelab operations SLO error budget."
      }

      label {
        key   = "service"
        value = "otel-collector"
      }

      label {
        key   = "signal"
        value = each.key
      }

      label {
        key   = "team"
        value = "homelab-operations"
      }
    }
  }
}
