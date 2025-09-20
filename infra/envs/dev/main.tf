data "azurerm_client_config" "current" {}

# Get the signed-in user so we can add you as an initial member of the group
data "azuread_client_config" "current" {}

module "core" {
  source       = "../../modules/core"
  project_name = var.project_name
  location     = var.location
}

module "iam" {
  source                    = "../../modules/iam"
  group_display_name        = "sql-administrators-dev"
  initial_member_object_ids = [data.azuread_client_config.current.object_id]
}

module "data" {
  source                = "../../modules/data"
  project_name          = var.project_name
  location              = var.location
  resource_group_name   = module.core.rg_name
  privatelink_subnet_id = module.core.privatelink_subnet_id
  tenant_id             = data.azurerm_client_config.current.tenant_id
  # Use the GROUP as SQL AAD admin
  aad_admin_login         = module.iam.sql_admin_group_displayname
  aad_admin_object_id     = module.iam.sql_admin_group_object_id
  sql_private_dns_zone_id = module.core.private_dns_sql_id
}

module "seedstore" {
  source                   = "../../modules/seedstore"
  project_name             = var.project_name
  location                 = var.location
  resource_group_name      = module.core.rg_name
  privatelink_subnet_id    = module.core.privatelink_subnet_id
  blob_private_dns_zone_id = module.core.private_dns_blob_id
}

module "web" {
  source                         = "../../modules/web"
  project_name                   = var.project_name
  location                       = var.location
  resource_group_name            = module.core.rg_name
  vnet_subnet_id                 = module.core.web_subnet_id
  app_insights_connection_string = module.core.appi_connection_string
  sql_server_fqdn                = module.data.sql_server_fqdn
  sql_database_name              = module.data.sql_db_name
  seed_blob_url                  = module.seedstore.seed_blob_url
  seed_storage_account_id        = module.seedstore.storage_account_id
  privatelink_subnet_id          = module.core.privatelink_subnet_id
  web_private_dns_zone_id        = module.core.private_dns_web_id
}

module "edge" {
  source                  = "../../modules/edge"
  project_name            = var.project_name
  resource_group_name     = module.core.rg_name
  origin_hostname         = module.web.web_default_hostname

  # your existing Azure DNS zone (already created)
  zone_name               = "${var.project_domain}"
  dns_zone_resource_group = "rg-app-domains"

  # apex primary + www for redirect
  apex_domain             = "${var.project_domain}"
  www_domain              = "www.${var.project_domain}"
}

# Outputs (unchanged except the sensitive one)
output "rg_name" { value = module.core.rg_name }
output "location" { value = module.core.location }
output "web_subnet_id" { value = module.core.web_subnet_id }
output "privatelink_subnet_id" { value = module.core.privatelink_subnet_id }
output "private_dns_sql_id" { value = module.core.private_dns_sql_id }
output "private_dns_blob_id" { value = module.core.private_dns_blob_id }
output "appi_connection_string" {
  value     = module.core.appi_connection_string
  sensitive = true
}
output "sql_server_fqdn" { value = module.data.sql_server_fqdn }
output "sql_db_name" { value = module.data.sql_db_name }
output "storage_account_name" { value = module.seedstore.storage_account_name }
output "seed_blob_url" { value = module.seedstore.seed_blob_url }
output "webapp_name" { value = module.web.webapp_name }
output "frontdoor_endpoint" { value = module.edge.frontdoor_endpoint_hostname }