variable "project_name"            { type = string }
variable "location"                { type = string }
variable "resource_group_name"     { type = string }
variable "privatelink_subnet_id"   { type = string }
variable "tenant_id"               { type = string }
variable "aad_admin_login"         { type = string }
variable "aad_admin_object_id"     { type = string }
variable "sql_private_dns_zone_id" { type = string }

resource "azurerm_mssql_server" "sql" {
  name                          = "sql-${var.project_name}-dev"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = "12.0"
  public_network_access_enabled = false
  identity { type = "SystemAssigned" }

  azuread_administrator {
    login_username = var.aad_admin_login
    object_id      = var.aad_admin_object_id
    tenant_id      = var.tenant_id
    azuread_authentication_only = true
  }
}

resource "azurerm_mssql_database" "db" {
  name      = "db-${var.project_name}-dev"
  server_id = azurerm_mssql_server.sql.id

  # General Purpose serverless (Gen5 1 vCore)
  sku_name                      = "GP_S_Gen5_1"
  min_capacity                  = 0.5          # REQUIRED for serverless
  auto_pause_delay_in_minutes   = 60           # optional – pause after 60m idle
  max_size_gb                   = 5            # keep cost small
  zone_redundant                = false        # serverless GP doesn't support ZR
}

resource "azurerm_private_endpoint" "pe_sql" {
  name                = "pe-sql"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.privatelink_subnet_id

  private_service_connection {
    name                           = "sql-link"
    private_connection_resource_id = azurerm_mssql_server.sql.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "sql-zone-group"
    private_dns_zone_ids = [var.sql_private_dns_zone_id]
  }
}

output "sql_server_fqdn" { value = azurerm_mssql_server.sql.fully_qualified_domain_name }
output "sql_db_name"     { value = azurerm_mssql_database.db.name }