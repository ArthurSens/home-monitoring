resource "grafana_slo" "hydration" {
  name        = "Hydration daily target"
  description = "Tracks whether daily Garmin hydration intake reaches the configured goal plus sweat loss."

  query {
    type = "freeform"

    freeform {
      query = <<-PROMQL
        (
          sum(
            max_over_time(garmin_hydration_intake_ml[$__rate_interval])
            >= bool
            (
              max_over_time(garmin_hydration_goal_ml[$__rate_interval])
              +
              max_over_time(garmin_hydration_sweat_loss_ml[$__rate_interval])
            )
          )
          and on() (hour(vector(time() - 3 * 3600)) >= 21)
        )
        /
        (
          sum(
            (
              max_over_time(garmin_hydration_goal_ml[$__rate_interval])
              +
              max_over_time(garmin_hydration_sweat_loss_ml[$__rate_interval])
            ) > bool 0
          )
          and on() (hour(vector(time() - 3 * 3600)) >= 21)
        )
        or
        (
          vector(1)
          and on() (hour(vector(time() - 3 * 3600)) < 21)
        )
      PROMQL
    }
  }

  objectives {
    value  = var.hydration_slo_objective
    window = var.hydration_slo_window
  }

  destination_datasource {
    uid = var.prometheus_datasource_uid
  }

  label {
    key   = "service"
    value = "hydration"
  }

  label {
    key   = "team"
    value = "garmin-health"
  }

  alerting {
    fastburn {
      annotation {
        key   = "name"
        value = "Hydration SLO fast burn"
      }

      annotation {
        key   = "description"
        value = "Daily hydration target misses are burning the hydration SLO error budget quickly."
      }

      label {
        key   = "service"
        value = "hydration"
      }

      label {
        key   = "team"
        value = "garmin-health"
      }
    }

    slowburn {
      annotation {
        key   = "name"
        value = "Hydration SLO slow burn"
      }

      annotation {
        key   = "description"
        value = "Daily hydration target misses are gradually burning the hydration SLO error budget."
      }

      label {
        key   = "service"
        value = "hydration"
      }

      label {
        key   = "team"
        value = "garmin-health"
      }
    }
  }
}
