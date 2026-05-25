resource "grafana_team" "garmin_health" {
  name    = "garmin-health"
  members = var.grafana_team_members
}

data "grafana_oncall_team" "garmin_health" {
  provider = grafana.oncall

  name = grafana_team.garmin_health.name
}
