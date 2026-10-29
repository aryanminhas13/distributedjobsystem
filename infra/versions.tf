terraform {
  required_version = ">= 1.8.0"
  backend "azurerm" {}
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm", version = "~> 4.50"
    }
    azapi = {
      source = "Azure/azapi", version = "~> 2.0"
    }
    random = {
      source = "hashicorp/random", version = "~> 3.6"
    }
    null = {
      source = "hashicorp/null", version = "~> 3.2"
    }
    time = {
      source = "hashicorp/time", version = "~> 0.12"
    }

  }
}

provider "azurerm" {
  features {}
}
provider "azapi" {}

data "azurerm_client_config" "current" {}
