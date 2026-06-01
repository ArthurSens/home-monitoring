resource "grafana_team" "garmin_health" {
  name    = "garmin-health"
  members = var.grafana_team_members
}

resource "grafana_team" "homelab_operations" {
  name    = "homelab-operations"
  members = var.homelab_ops_team_members
}

data "grafana_oncall_team" "garmin_health" {
  provider = grafana.oncall

  name = grafana_team.garmin_health.name
}

data "grafana_oncall_team" "homelab_operations" {
  provider = grafana.oncall

  name = grafana_team.homelab_operations.name
}
