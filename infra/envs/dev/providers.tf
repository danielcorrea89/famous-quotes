terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.109.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.50.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }

  backend "azurerm" {
    subscription_id      = "e7cbc1ca-744a-432a-b54b-dd8b5a2d2799"
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stfamousquotestfstate"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = "e7cbc1ca-744a-432a-b54b-dd8b5a2d2799"
  tenant_id       = "6f1b261a-5960-45a0-8020-a29b8000417a"
  use_cli         = true
}

provider "azuread" {
  # uses your az login context
}