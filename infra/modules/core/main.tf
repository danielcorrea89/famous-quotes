# core module – fix random_integer to multi-line form (and keep everything else the same)
variable "project_name" { type = string }
variable "location"     { type = string }

# resource "random_integer" "rand" {
#   min = 10000
#   max = 99999
# }

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.project_name}-dev"
  location = var.location
}

# VNet + subnets
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.project_name}-dev"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  address_space       = ["10.20.0.0/16"]
}

# Delegated subnet for App Service VNet Integration
resource "azurerm_subnet" "web" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.20.1.0/24"]
  delegation {
    name = "appsvc"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Subnet for Private Endpoints (SQL, Storage, KV later)
resource "azurerm_subnet" "privatelink" {
  name                                           = "snet-privatelink"
  resource_group_name                            = azurerm_resource_group.rg.name
  virtual_network_name                           = azurerm_virtual_network.vnet.name
  address_prefixes                               = ["10.20.10.0/24"]
  private_link_service_network_policies_enabled = true
}

# Log Analytics + App Insights
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${var.project_name}-dev"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "appi" {
  name                = "appi-${var.project_name}-dev"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.law.id
}

# Private DNS zones for Private Endpoints (SQL + Blob)
resource "azurerm_private_dns_zone" "privsql" {
  name                = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone" "privblob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

# Link zones to the VNet
resource "azurerm_private_dns_zone_virtual_network_link" "link_sql" {
  name                  = "link-sql"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.privsql.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "link_blob" {
  name                  = "link-blob"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.privblob.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

# Outputs
output "rg_name"               { value = azurerm_resource_group.rg.name }
output "location"              { value = var.location }
output "web_subnet_id"         { value = azurerm_subnet.web.id }
output "privatelink_subnet_id" { value = azurerm_subnet.privatelink.id }
output "private_dns_sql_id"    { value = azurerm_private_dns_zone.privsql.id }
output "private_dns_blob_id"   { value = azurerm_private_dns_zone.privblob.id }
output "appi_connection_string" { value = azurerm_application_insights.appi.connection_string }