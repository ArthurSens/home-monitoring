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

variable "hydration_slo_window" {
  description = "Grafana SLO objective window. Grafana SLO requires at least 7d."
  type        = string
  default     = "7d"
}

variable "hydration_slo_objective" {
  description = "Fraction of days in the SLO window where hydration should reach the daily target."
  type        = number
  default     = 0.95
}

variable "oncall_user_ids" {
  description = "Grafana IRM user IDs to include in the hydration on-call schedule."
  type        = list(string)
}

variable "grafana_team_members" {
  description = "Grafana user email addresses to include in the garmin-health team."
  type        = set(string)
}
