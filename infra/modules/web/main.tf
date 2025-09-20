variable "project_name"                   { type = string }
variable "location"                       { type = string }
variable "resource_group_name"            { type = string }
variable "vnet_subnet_id"                 { type = string }
variable "app_insights_connection_string" { type = string }
variable "sql_server_fqdn"                { type = string }
variable "sql_database_name"              { type = string }
variable "seed_blob_url"                  { type = string }
variable "seed_storage_account_id"        { type = string }

resource "azurerm_service_plan" "plan" {
  name                = "asp-${var.project_name}-dev"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "P1v3"
  zone_balancing_enabled = true
}

resource "azurerm_linux_web_app" "app" {
  name                = "app-${var.project_name}-dev"
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.plan.id
  https_only          = true

  site_config {
    always_on = true
    application_stack { dotnet_version = "8.0" }
  }

  identity { type = "SystemAssigned" }

  app_settings = {
    "ApplicationInsights__ConnectionString" = var.app_insights_connection_string
    "Sql__Server"   = var.sql_server_fqdn
    "Sql__Database" = var.sql_database_name
    "Seed__BlobUrl" = var.seed_blob_url
  }
}

resource "azurerm_app_service_virtual_network_swift_connection" "vnet" {
  app_service_id = azurerm_linux_web_app.app.id
  subnet_id      = var.vnet_subnet_id
}

# WebApp MI can read seed blob
resource "azurerm_role_assignment" "seed_reader" {
  scope                = var.seed_storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_linux_web_app.app.identity[0].principal_id
}

output "web_default_hostname" { value = azurerm_linux_web_app.app.default_hostname }
output "webapp_name"          { value = azurerm_linux_web_app.app.name }