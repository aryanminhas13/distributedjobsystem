output "dashboard_url" {
  value = "https://${azurerm_container_app.dashboard.ingress[0].fqdn}"
}
output "resource_group_name" {
  value = azurerm_resource_group.main.name
}
output "container_registry" {
  value = azurerm_container_registry.main.login_server
}
output "key_vault_name" {
  value = azurerm_key_vault.main.name
}
output "admin_token_secret_uri" {
  value     = azurerm_key_vault_secret.admin_token.versionless_id
  sensitive = true
}
output "application_insights_name" {
  value = azurerm_application_insights.main.name
}
