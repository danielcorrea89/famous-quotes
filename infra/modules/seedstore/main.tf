variable "project_name"             { type = string }
variable "location"                 { type = string }
variable "resource_group_name"      { type = string }
variable "privatelink_subnet_id"    { type = string }
variable "blob_private_dns_zone_id" { type = string }

# resource "random_integer" "rand" {
#   min = 10000
#   max = 99999
# }

resource "azurerm_storage_account" "sa" {
  name                          = "st${var.project_name}dev"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  account_kind                  = "StorageV2"
  min_tls_version               = "TLS1_2"
  https_traffic_only_enabled    = true

  # Allow public network so Terraform/your laptop can hit the data plane.
  # (We already protect blobs from being public.)
  public_network_access_enabled = true
}

resource "azurerm_storage_container" "seed" {
  name                  = "seed"
  storage_account_id    = azurerm_storage_account.sa.id
  container_access_type = "private"
}

resource "azurerm_private_endpoint" "pe_blob" {
  name                = "pe-blob"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.privatelink_subnet_id

  private_service_connection {
    name                           = "blob-link"
    private_connection_resource_id = azurerm_storage_account.sa.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob-zone-group"
    private_dns_zone_ids = [var.blob_private_dns_zone_id]
  }
}

output "storage_account_id"   { value = azurerm_storage_account.sa.id }
output "storage_account_name" { value = azurerm_storage_account.sa.name }
output "seed_blob_url" {
  value = "https://${azurerm_storage_account.sa.name}.blob.core.windows.net/${azurerm_storage_container.seed.name}/quotes.json"
}