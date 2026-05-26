resource "grafana_folder" "hydration_alerts" {
  title = "Hydration"
}

resource "grafana_rule_group" "hydration_pace" {
  name             = "Hydration pace"
  folder_uid       = grafana_folder.hydration_alerts.uid
  interval_seconds = 60

  rule {
    name           = "Hydration behind pace"
    condition      = "C"
    for            = "30m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    is_paused      = false

    annotations = {
      description = "Hydration intake is not on track to reach today's Garmin goal plus sweat loss by 9 PM."
      summary     = "Hydration is behind pace"
    }

    labels = {
      service  = "hydration"
      severity = "warning"
      team     = "garmin-health"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 10800
        to   = 0
      }

      model = jsonencode({
        datasource = {
          type = "prometheus"
          uid  = var.prometheus_datasource_uid
        }
        editorMode    = "code"
        expr          = <<-PROMQL
          (
            predict_linear(
              garmin_hydration_intake_ml[3h],
              scalar(
                (21 - hour(vector(time() - 3 * 3600))) * 3600
                - minute(vector(time() - 3 * 3600)) * 60
              )
            )
              < bool (garmin_hydration_goal_ml + garmin_hydration_sweat_loss_ml)
          )
            and (garmin_hydration_goal_ml + garmin_hydration_sweat_loss_ml) > 0
            and on() (hour(vector(time() - 3 * 3600)) >= 8)
            and on() (hour(vector(time() - 3 * 3600)) < 21)
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

resource "grafana_contact_point" "hydration_slo_irm" {
  name = "Hydration SLO IRM"

  oncall {
    url = grafana_oncall_integration.hydration_slo.link
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
}
