locals {
  hydration_slo_utc_offset_seconds = 3 * 3600
  hydration_slo_daily_window       = "18h"

  hydration_slo_daily_intake_query = <<-PROMQL
    max without (instance, service_instance_id) (
      max_over_time(garmin_hydration_intake_ml[${local.hydration_slo_daily_window}:$__rate_interval])
    )
  PROMQL

  hydration_slo_daily_target_query = <<-PROMQL
    (
      (
        max without (instance, service_instance_id) (
          max_over_time(garmin_hydration_goal_ml[${local.hydration_slo_daily_window}:$__rate_interval])
        )
        +
        max without (instance, service_instance_id) (
          max_over_time(garmin_hydration_sweat_loss_ml[${local.hydration_slo_daily_window}:$__rate_interval])
        )
      )
      or
      max without (instance, service_instance_id) (
        max_over_time(garmin_hydration_goal_ml[${local.hydration_slo_daily_window}:$__rate_interval])
      )
    )
  PROMQL

  hydration_slo_daily_ratio_query = <<-PROMQL
    (
      sum(
        ${indent(8, local.hydration_slo_daily_intake_query)}
        >= bool
        ${indent(8, local.hydration_slo_daily_target_query)}
      )
      /
      sum(
        ${indent(8, local.hydration_slo_daily_target_query)} > bool 0
      )
    )
    and on()
    sum(
      ${indent(6, local.hydration_slo_daily_target_query)} > bool 0
    ) > 0
  PROMQL

  hydration_slo_previous_day_query = join("\n        or\n", [
    for local_hour in range(24) : <<-PROMQL
      (
        last_over_time(
          (
            ${indent(8, local.hydration_slo_daily_ratio_query)}
            and on() (hour(vector(time() - ${local.hydration_slo_utc_offset_seconds})) >= 23)
            and on() (hour(vector(time() - ${local.hydration_slo_utc_offset_seconds})) < 24)
          )[2h:1m] offset ${local_hour}h
        )
        and on() (hour(vector(time() - ${local.hydration_slo_utc_offset_seconds})) == ${local_hour})
      )
    PROMQL
  ])
}

resource "grafana_slo" "hydration" {
  name        = "Hydration daily target"
  description = "Tracks whether daily Garmin hydration intake reaches the configured goal plus sweat loss."

  query {
    type = "freeform"

    freeform {
      query = <<-PROMQL
        ${indent(8, local.hydration_slo_previous_day_query)}
        or vector(1)
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
