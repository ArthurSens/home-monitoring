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
