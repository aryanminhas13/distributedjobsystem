resource "azurerm_consumption_budget_resource_group" "main" {
  name              = "budget-${local.prefix}"
  resource_group_id = azurerm_resource_group.main.id
  amount            = var.monthly_budget_cad
  time_grain        = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }

  dynamic "notification" {
    for_each = var.alert_email == "" ? [] : [var.alert_email]
    content {
      enabled        = true
      threshold      = 80
      operator       = "GreaterThan"
      threshold_type = "Actual"
      contact_emails = [notification.value]
    }
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}
