variable "grafana_url" {
  description = "Grafana Cloud stack URL."
  type        = string
}

variable "grafana_auth" {
  description = "Grafana Cloud service account token with SLO and IRM permissions."
  type        = string
  sensitive   = true
}

variable "grafana_oncall_url" {
  description = "Grafana IRM API URL from Alerts & IRM > IRM > Settings > Admin & API."
  type        = string
}

variable "prometheus_datasource_uid" {
  description = "Grafana Cloud Prometheus datasource UID used by Grafana SLO."
  type        = string
  default     = "grafanacloud-prom"
}

variable "collector_export_slo_window" {
  description = "Grafana SLO objective window for collector export reliability."
  type        = string
  default     = "30d"
}

variable "collector_export_slo_objective" {
  description = "Fraction of collector telemetry items exported successfully in the SLO window."
  type        = number
  default     = 0.995
}

variable "homelab_ops_oncall_user_ids" {
  description = "Grafana IRM user IDs to include in the homelab operations on-call schedule."
  type        = list(string)
}

variable "grafana_team_members" {
  description = "Grafana user email addresses to include in the garmin-health team."
  type        = set(string)
}

variable "homelab_ops_team_members" {
  description = "Grafana user email addresses to include in the homelab-operations team."
  type        = set(string)
}
