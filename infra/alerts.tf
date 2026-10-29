resource "azurerm_monitor_action_group" "main" {
  name                = "ag-${local.prefix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "djobs"
  dynamic "email_receiver" {
    for_each = var.alert_email == "" ? [] : [var.alert_email]
    content {
      name          = "platform-owner"
      email_address = email_receiver.value
    }
  }
  tags = local.tags
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "error_rate" {
  name                 = "alert-${local.prefix}-error-rate"
  resource_group_name  = azurerm_resource_group.main.name
  location             = var.location
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  scopes               = [azurerm_application_insights.main.id]
  severity             = 1
  description          = "5xx/error rate exceeds the 99.9% availability SLO"
  enabled              = true
  criteria {
    query                   = "requests | summarize total=count(), failed=countif(success == false) | extend error_rate=100.0*failed/total | where total >= 20 and error_rate > 0.1"
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }
  action {
    action_groups = [azurerm_monitor_action_group.main.id]
  }
  tags = local.tags
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "latency" {
  name                 = "alert-${local.prefix}-latency"
  resource_group_name  = azurerm_resource_group.main.name
  location             = var.location
  evaluation_frequency = "PT5M"
  window_duration      = "PT15M"
  scopes               = [azurerm_application_insights.main.id]
  severity             = 2
  description          = "HTTP p95 latency exceeds 150 ms"
  enabled              = true
  criteria {
    query                   = "requests | summarize p95_ms=percentile(duration/1ms,95) | where p95_ms > 150"
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 2
      number_of_evaluation_periods             = 3
    }
  }
  action {
    action_groups = [azurerm_monitor_action_group.main.id]
  }
  tags = local.tags
}
