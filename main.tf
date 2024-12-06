terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Create Log analytics workspace
resource "azurerm_log_analytics_workspace" "log_analytics" {
  name                  = "aks-log-workspace"
  location              = "Canada Central"
  resource_group_name   = "rg-webgoat"
  sku                   = "PerGB2018"
  retention_in_days     = 30
  
  tags = {
    environment = "Develop"
  }
}


resource "azurerm_kubernetes_cluster" "aks" {
  name                = "webGoatCluster"
  location            = "Canada Central"
  resource_group_name = "rg-webgoat"
  dns_prefix          = "webgoatk8cluster"

  default_node_pool {
    name                    = "default"
    vm_size                 = "Standard_B2s"
    auto_scaling_enabled    = true
    min_count               = 1
    max_count               = 3
  }

  identity {
    type = "SystemAssigned"
  }

  role_based_access_control_enabled = true

# Link AKS with log analytics for monitoring
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics.id
  }

  tags = {
    environment = "Develop"
  }
}