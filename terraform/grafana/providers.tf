provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_auth
}

provider "grafana" {
  alias      = "oncall"
  url        = var.grafana_url
  auth       = var.grafana_auth
  oncall_url = var.grafana_oncall_url
}
