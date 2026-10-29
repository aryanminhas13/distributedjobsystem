locals {
  prefix = "${var.project}-${var.environment}-${random_id.suffix.hex}"
  tags = merge(var.tags, {
    environment = var.environment
  })
  api_image       = "${azurerm_container_registry.main.login_server}/job-api:${filesha256("${path.module}/../server/main.go")}"
  dashboard_image = "${azurerm_container_registry.main.login_server}/job-dashboard:${filesha256("${path.module}/../dashboard/src.tsx")}"
}

resource "random_id" "suffix" {
  byte_length = 3
}
resource "random_password" "postgres" {
  length           = 32
  special          = true
  override_special = "-_"
}
resource "random_password" "admin_token" {
  length  = 48
  special = false
}
resource "random_password" "operator_token" {
  length  = 48
  special = false
}
resource "random_password" "viewer_token" {
  length  = 48
  special = false
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.prefix}"
  location = var.location
  tags     = local.tags
}
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${local.prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}
resource "azurerm_application_insights" "main" {
  name                         = "appi-${local.prefix}"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.main.name
  workspace_id                 = azurerm_log_analytics_workspace.main.id
  application_type             = "web"
  local_authentication_enabled = true
  tags                         = local.tags
}

resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${local.prefix}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.tags
}
resource "azapi_update_resource" "otel" {
  type        = "Microsoft.App/managedEnvironments@2023-11-02-preview"
  resource_id = azurerm_container_app_environment.main.id
  body = {
    properties = {
      appInsightsConfiguration = {
        connectionString = azurerm_application_insights.main.connection_string
      }
      openTelemetryConfiguration = {
        tracesConfiguration = {
          destinations = ["appInsights"]
        }
        logsConfiguration = {
          destinations = ["appInsights"]
        }
      }
    }
  }
}

resource "azurerm_container_registry" "main" {
  name                = replace("acr${local.prefix}", "-", "")
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}
resource "azurerm_user_assigned_identity" "workload" {
  name                = "id-${local.prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.tags
}
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

resource "azurerm_key_vault" "main" {
  name                       = substr("kv-${local.prefix}", 0, 24)
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
  tags                       = local.tags
}
resource "azurerm_role_assignment" "deployer_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
resource "azurerm_role_assignment" "workload_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}
resource "time_sleep" "rbac" {
  depends_on      = [azurerm_role_assignment.deployer_secrets, azurerm_role_assignment.workload_secrets]
  create_duration = "30s"
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                          = "psql-${local.prefix}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = var.location
  version                       = "16"
  administrator_login           = var.postgres_admin
  administrator_password        = random_password.postgres.result
  sku_name                      = "B_Standard_B1ms"
  storage_mb                    = 32768
  backup_retention_days         = 7
  geo_redundant_backup_enabled  = false
  public_network_access_enabled = true
  tags                          = local.tags
}
resource "azurerm_postgresql_flexible_server_database" "jobs" {
  name      = "jobs"
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_managed_redis" "main" {
  name                      = "redis-${local.prefix}"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.main.name
  sku_name                  = "Balanced_B0"
  high_availability_enabled = true
  public_network_access     = "Enabled"
  tags                      = local.tags

  default_database {
    access_keys_authentication_enabled = true
    client_protocol                    = "Encrypted"
    clustering_policy                  = "NoCluster"
    eviction_policy                    = "NoEviction"
  }
}

resource "azurerm_key_vault_secret" "database_url" {
  name         = "database-url"
  value        = "postgres://${var.postgres_admin}:${urlencode(random_password.postgres.result)}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/jobs?sslmode=require"
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [time_sleep.rbac, azurerm_postgresql_flexible_server_database.jobs]
}
resource "azurerm_key_vault_secret" "redis_url" {
  name         = "redis-url"
  value        = "rediss://:${urlencode(azurerm_managed_redis.main.default_database[0].primary_access_key)}@${azurerm_managed_redis.main.hostname}:${azurerm_managed_redis.main.default_database[0].port}/0"
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [time_sleep.rbac]
}
resource "azurerm_key_vault_secret" "admin_token" {
  name         = "admin-token"
  value        = random_password.admin_token.result
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [time_sleep.rbac]
}
resource "azurerm_key_vault_secret" "operator_token" {
  name         = "operator-token"
  value        = random_password.operator_token.result
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [time_sleep.rbac]
}
resource "azurerm_key_vault_secret" "viewer_token" {
  name         = "viewer-token"
  value        = random_password.viewer_token.result
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [time_sleep.rbac]
}

resource "null_resource" "build_api" {
  triggers = {
    source_hash = sha256(join("", [for f in fileset("${path.module}/../server", "**") : filesha256("${path.module}/../server/${f}")]))
  }
  provisioner "local-exec" {
    command = "az acr build --registry ${azurerm_container_registry.main.name} --image job-api:${filesha256("${path.module}/../server/main.go")} ${path.module}/../server"
  }
}
resource "null_resource" "build_dashboard" {
  triggers = {
    source_hash = sha256(join("", [for f in fileset("${path.module}/../dashboard", "**") : filesha256("${path.module}/../dashboard/${f}")]))
  }
  provisioner "local-exec" {
    command = "az acr build --registry ${azurerm_container_registry.main.name} --image job-dashboard:${filesha256("${path.module}/../dashboard/src.tsx")} ${path.module}/../dashboard"
  }
}

resource "azurerm_container_app" "api" {
  name                         = "api-${local.prefix}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.tags
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.workload.id]
  }
  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.workload.id
  }
  secret {
    name                = "database-url"
    key_vault_secret_id = azurerm_key_vault_secret.database_url.versionless_id
    identity            = azurerm_user_assigned_identity.workload.id
  }
  secret {
    name                = "redis-url"
    key_vault_secret_id = azurerm_key_vault_secret.redis_url.versionless_id
    identity            = azurerm_user_assigned_identity.workload.id
  }
  secret {
    name                = "admin-token"
    key_vault_secret_id = azurerm_key_vault_secret.admin_token.versionless_id
    identity            = azurerm_user_assigned_identity.workload.id
  }
  secret {
    name                = "operator-token"
    key_vault_secret_id = azurerm_key_vault_secret.operator_token.versionless_id
    identity            = azurerm_user_assigned_identity.workload.id
  }
  secret {
    name                = "viewer-token"
    key_vault_secret_id = azurerm_key_vault_secret.viewer_token.versionless_id
    identity            = azurerm_user_assigned_identity.workload.id
  }
  template {
    min_replicas = 2
    max_replicas = 10
    container {
      name   = "api"
      image  = local.api_image
      cpu    = 0.5
      memory = "1Gi"
      env {
        name  = "APP_ENV"
        value = var.environment
      }
      env {
        name  = "OTEL_SERVICE_NAME"
        value = "job-api"
      }
      env {
        name        = "DATABASE_URL"
        secret_name = "database-url"
      }
      env {
        name        = "REDIS_URL"
        secret_name = "redis-url"
      }
      env {
        name        = "ADMIN_TOKEN"
        secret_name = "admin-token"
      }
      env {
        name        = "OPERATOR_TOKEN"
        secret_name = "operator-token"
      }
      env {
        name        = "VIEWER_TOKEN"
        secret_name = "viewer-token"
      }
      liveness_probe {
        transport        = "HTTP"
        port             = 8080
        path             = "/healthz"
        initial_delay    = 10
        interval_seconds = 15
      }
      readiness_probe {
        transport        = "HTTP"
        port             = 8080
        path             = "/healthz"
        interval_seconds = 10
      }
    }
    http_scale_rule {
      name                = "http"
      concurrent_requests = 50
    }

  }
  ingress {
    external_enabled = false
    target_port      = 8080
    transport        = "http"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
  depends_on = [null_resource.build_api, azurerm_role_assignment.acr_pull, azapi_update_resource.otel]
}

resource "azurerm_container_app" "worker" {
  name                         = "worker-${local.prefix}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.tags
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.workload.id]
  }
  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.workload.id
  }
  secret {
    name                = "database-url"
    key_vault_secret_id = azurerm_key_vault_secret.database_url.versionless_id
    identity            = azurerm_user_assigned_identity.workload.id
  }
  secret {
    name                = "redis-url"
    key_vault_secret_id = azurerm_key_vault_secret.redis_url.versionless_id
    identity            = azurerm_user_assigned_identity.workload.id
  }
  template {
    min_replicas = var.worker_min_replicas
    max_replicas = var.worker_max_replicas
    container {
      name   = "worker"
      image  = local.api_image
      args   = ["worker"]
      cpu    = 0.5
      memory = "1Gi"
      env {
        name  = "APP_ENV"
        value = var.environment
      }
      env {
        name  = "OTEL_SERVICE_NAME"
        value = "job-worker"
      }
      env {
        name        = "DATABASE_URL"
        secret_name = "database-url"
      }
      env {
        name        = "REDIS_URL"
        secret_name = "redis-url"
      }
    }
    custom_scale_rule {
      name             = "cpu"
      custom_rule_type = "cpu"
      metadata = {
        type = "Utilization", value = "60"
      }
    }

  }
  depends_on = [null_resource.build_api, azurerm_role_assignment.acr_pull, azapi_update_resource.otel]
}

resource "azurerm_container_app" "dashboard" {
  name                         = "dashboard-${local.prefix}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.tags
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.workload.id]
  }
  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.workload.id
  }
  template {
    min_replicas = 1
    max_replicas = 5
    container {
      name   = "dashboard"
      image  = local.dashboard_image
      cpu    = 0.25
      memory = "0.5Gi"
      env {
        name  = "API_UPSTREAM"
        value = "https://${azurerm_container_app.api.ingress[0].fqdn}"
      }
      liveness_probe {
        transport        = "HTTP"
        port             = 80
        path             = "/"
        initial_delay    = 5
        interval_seconds = 15
      }
    }
    http_scale_rule {
      name                = "http"
      concurrent_requests = 100
    }
  }
  ingress {
    external_enabled           = true
    target_port                = 80
    transport                  = "http"
    allow_insecure_connections = false
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
  depends_on = [null_resource.build_dashboard, azurerm_role_assignment.acr_pull]
}
