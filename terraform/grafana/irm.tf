resource "grafana_oncall_on_call_shift" "homelab_operations_primary" {
  provider = grafana.oncall

  name      = "Homelab operations primary"
  type      = "rolling_users"
  start     = "2026-06-01T00:00:00"
  duration  = 60 * 60 * 24
  frequency = "daily"
  interval  = 1
  time_zone = "America/Sao_Paulo"
  team_id   = data.grafana_oncall_team.homelab_operations.id
  rolling_users = [
    var.homelab_ops_oncall_user_ids,
  ]
}

resource "grafana_oncall_schedule" "homelab_operations" {
  provider = grafana.oncall

  name      = "Homelab operations"
  type      = "calendar"
  time_zone = "America/Sao_Paulo"
  team_id   = data.grafana_oncall_team.homelab_operations.id
  shifts = [
    grafana_oncall_on_call_shift.homelab_operations_primary.id,
  ]
}

resource "grafana_oncall_escalation_chain" "homelab_operations_warning" {
  provider = grafana.oncall

  name    = "Homelab operations warning"
  team_id = data.grafana_oncall_team.homelab_operations.id
}

resource "grafana_oncall_escalation" "homelab_operations_warning_notify_schedule" {
  provider = grafana.oncall

  escalation_chain_id          = grafana_oncall_escalation_chain.homelab_operations_warning.id
  type                         = "notify_on_call_from_schedule"
  notify_on_call_from_schedule = grafana_oncall_schedule.homelab_operations.id
  position                     = 0
}

resource "grafana_oncall_escalation_chain" "homelab_operations_critical" {
  provider = grafana.oncall

  name    = "Homelab operations critical"
  team_id = data.grafana_oncall_team.homelab_operations.id
}

resource "grafana_oncall_escalation" "homelab_operations_critical_notify_schedule" {
  provider = grafana.oncall

  escalation_chain_id          = grafana_oncall_escalation_chain.homelab_operations_critical.id
  type                         = "notify_on_call_from_schedule"
  notify_on_call_from_schedule = grafana_oncall_schedule.homelab_operations.id
  important                    = true
  position                     = 0
}

resource "grafana_oncall_escalation" "homelab_operations_critical_wait" {
  provider = grafana.oncall

  escalation_chain_id = grafana_oncall_escalation_chain.homelab_operations_critical.id
  type                = "wait"
  duration            = 300
  position            = 1
}

resource "grafana_oncall_escalation" "homelab_operations_critical_repeat" {
  provider = grafana.oncall

  escalation_chain_id = grafana_oncall_escalation_chain.homelab_operations_critical.id
  type                = "repeat_escalation"
  position            = 2
}

resource "grafana_oncall_integration" "homelab_operations" {
  provider = grafana.oncall

  name    = "Homelab operations"
  type    = "grafana_alerting"
  team_id = data.grafana_oncall_team.homelab_operations.id

  default_route {
    escalation_chain_id = grafana_oncall_escalation_chain.homelab_operations_warning.id
  }
}

resource "grafana_oncall_route" "homelab_operations_warning" {
  provider = grafana.oncall

  integration_id      = grafana_oncall_integration.homelab_operations.id
  escalation_chain_id = grafana_oncall_escalation_chain.homelab_operations_warning.id
  routing_type        = "jinja2"
  routing_regex       = "{{ labels.team == \"homelab-operations\" and labels.severity == \"warning\" }}"
  position            = 0
}

resource "grafana_oncall_route" "homelab_operations_slo_warning" {
  provider = grafana.oncall

  integration_id      = grafana_oncall_integration.homelab_operations.id
  escalation_chain_id = grafana_oncall_escalation_chain.homelab_operations_warning.id
  routing_type        = "jinja2"
  routing_regex       = "{{ labels.team == \"homelab-operations\" and labels.grafana_slo_severity == \"warning\" }}"
  position            = 1
}

resource "grafana_oncall_route" "homelab_operations_critical" {
  provider = grafana.oncall

  integration_id      = grafana_oncall_integration.homelab_operations.id
  escalation_chain_id = grafana_oncall_escalation_chain.homelab_operations_critical.id
  routing_type        = "jinja2"
  routing_regex       = "{{ labels.team == \"homelab-operations\" and (labels.grafana_slo_severity == \"critical\" or labels.severity == \"critical\") }}"
  position            = 2
}
