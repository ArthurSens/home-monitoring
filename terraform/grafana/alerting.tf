resource "grafana_folder" "hydration_alerts" {
  title = "Hydration"
}

resource "grafana_folder" "homelab_operations_alerts" {
  title = "Homelab Operations"
}

resource "grafana_rule_group" "hydration_pace" {
  name             = "Hydration pace"
  folder_uid       = grafana_folder.hydration_alerts.uid
  interval_seconds = 60

  rule {
    name           = "Hydration behind pace"
    condition      = "C"
    no_data_state  = "OK"
    exec_err_state = "Error"
    is_paused      = false

    annotations = {
      description = "Hydration intake is not on track to reach today's Garmin goal plus sweat loss by 7 PM."
      summary     = "Hydration is behind pace"
    }

    labels = {
      service  = "hydration"
      severity = "critical"
      team     = "garmin-health"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 21600
        to   = 0
      }

      model = jsonencode({
        datasource = {
          type = "prometheus"
          uid  = var.prometheus_datasource_uid
        }
        editorMode = "code"
        # PromQL time functions evaluate timestamps in UTC. Update this offset
        # whenever the hydration alert should follow a different local timezone.
        expr          = <<-PROMQL
          (
            predict_linear(
              garmin_hydration_intake_ml[6h],
              scalar(
                (19 - hour(vector(time() + 9 * 3600))) * 3600
                - minute(vector(time() + 9 * 3600)) * 60
              )
            )
              < bool ((garmin_hydration_goal_ml + garmin_hydration_sweat_loss_ml) or garmin_hydration_goal_ml)
          )
            and ((garmin_hydration_goal_ml + garmin_hydration_sweat_loss_ml) or garmin_hydration_goal_ml) > 0
            and on() (hour(vector(time() + 9 * 3600)) >= 7)
            and on() (hour(vector(time() + 9 * 3600)) < 19)
        PROMQL
        hide          = false
        instant       = true
        intervalMs    = 1000
        maxDataPoints = 43200
        range         = false
        refId         = "A"
      })
    }

    data {
      ref_id         = "B"
      datasource_uid = "__expr__"

      relative_time_range {
        from = 0
        to   = 0
      }

      model = jsonencode({
        datasource = {
          type = "__expr__"
          uid  = "__expr__"
        }
        expression    = "A"
        hide          = false
        intervalMs    = 1000
        maxDataPoints = 43200
        reducer       = "last"
        refId         = "B"
        type          = "reduce"
      })
    }

    data {
      ref_id         = "C"
      datasource_uid = "__expr__"

      relative_time_range {
        from = 0
        to   = 0
      }

      model = jsonencode({
        datasource = {
          type = "__expr__"
          uid  = "__expr__"
        }
        expression    = "$B > 0"
        hide          = false
        intervalMs    = 1000
        maxDataPoints = 43200
        refId         = "C"
        type          = "math"
      })
    }
  }
}

resource "grafana_rule_group" "loki_storage" {
  name             = "Loki storage"
  folder_uid       = grafana_folder.homelab_operations_alerts.uid
  interval_seconds = 60

  rule {
    name           = "Loki WAL disk usage high"
    condition      = "C"
    no_data_state  = "OK"
    exec_err_state = "Error"
    for            = "5m"
    is_paused      = false

    annotations = {
      description = "Loki WAL disk usage is above 95%, close to the configured 98% write-throttling threshold."
      summary     = "Loki WAL disk usage is close to capacity"
    }

    labels = {
      service  = "loki"
      severity = "warning"
      team     = "homelab-operations"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        datasource = {
          type = "prometheus"
          uid  = var.prometheus_datasource_uid
        }
        editorMode    = "code"
        expr          = "max(loki_ingester_wal_disk_usage_percent)"
        hide          = false
        instant       = true
        intervalMs    = 1000
        maxDataPoints = 43200
        range         = false
        refId         = "A"
      })
    }

    data {
      ref_id         = "B"
      datasource_uid = "__expr__"

      relative_time_range {
        from = 0
        to   = 0
      }

      model = jsonencode({
        datasource = {
          type = "__expr__"
          uid  = "__expr__"
        }
        expression    = "A"
        hide          = false
        intervalMs    = 1000
        maxDataPoints = 43200
        reducer       = "last"
        refId         = "B"
        type          = "reduce"
      })
    }

    data {
      ref_id         = "C"
      datasource_uid = "__expr__"

      relative_time_range {
        from = 0
        to   = 0
      }

      model = jsonencode({
        datasource = {
          type = "__expr__"
          uid  = "__expr__"
        }
        expression    = "$B > 0.95"
        hide          = false
        intervalMs    = 1000
        maxDataPoints = 43200
        refId         = "C"
        type          = "math"
      })
    }
  }
}

resource "grafana_contact_point" "hydration_slo_irm" {
  name = "Hydration SLO IRM"

  oncall {
    url = grafana_oncall_integration.hydration_slo.link
  }
}

resource "grafana_contact_point" "homelab_operations_irm" {
  name = "Homelab Operations IRM"

  oncall {
    url = grafana_oncall_integration.homelab_operations.link
  }
}

resource "grafana_notification_policy" "default" {
  contact_point = "grafana-default-email"
  group_by      = ["grafana_folder", "alertname"]

  policy {
    matcher {
      label = "service"
      match = "="
      value = "hydration"
    }

    matcher {
      label = "team"
      match = "="
      value = "garmin-health"
    }

    contact_point = grafana_contact_point.hydration_slo_irm.name
    group_by      = ["grafana_folder", "alertname"]
  }

  policy {
    matcher {
      label = "team"
      match = "="
      value = "homelab-operations"
    }

    contact_point = grafana_contact_point.homelab_operations_irm.name
    group_by      = ["grafana_folder", "alertname"]
  }
}
