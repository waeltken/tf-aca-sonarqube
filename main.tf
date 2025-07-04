provider "azurerm" {
  subscription_id = "eedea4b7-9139-440d-84b1-0b09522f109e"
  features {}
}

terraform {
  backend "azurerm" {
  }
}

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
  lower   = true
  numeric = true
}

resource "azurerm_resource_group" "main" {
  name     = "sonarqube-rg"
  location = "West Europe"
}

resource "azurerm_virtual_network" "main" {
  name                = "sonarqube-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/22"]
}

resource "azurerm_subnet" "aca" {
  name                 = "sonarqube-aca-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "aca-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "endpoints" {
  name                 = "sonarqube-endpoints-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "sonarqube-log-analytics"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_storage_account" "main" {
  name                     = "sonarqubestorage${random_string.suffix.result}"
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_container_app_environment" "main" {
  name                = "sonarqube-environment"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  workload_profile {
    name                  = "E8"
    workload_profile_type = "E8"
    maximum_count         = 1
    minimum_count         = 0
  }

  internal_load_balancer_enabled = false
  infrastructure_subnet_id       = azurerm_subnet.aca.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.main.id
}

resource "azurerm_storage_share" "data" {
  name               = "sonarqube-data"
  storage_account_id = azurerm_storage_account.main.id
  quota              = 5
}

resource "azurerm_storage_share" "logs" {
  name               = "sonarqube-logs"
  storage_account_id = azurerm_storage_account.main.id
  quota              = 5
}

resource "azurerm_storage_share" "extensions" {
  name               = "sonarqube-extensions"
  storage_account_id = azurerm_storage_account.main.id
  quota              = 5
}

resource "azurerm_container_app_environment_storage" "data" {
  name                         = "sonarqube-data"
  account_name                 = azurerm_storage_account.main.name
  access_key                   = azurerm_storage_account.main.primary_access_key
  container_app_environment_id = azurerm_container_app_environment.main.id
  share_name                   = azurerm_storage_share.data.name
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app_environment_storage" "logs" {
  name                         = "sonarqube-logs"
  account_name                 = azurerm_storage_account.main.name
  access_key                   = azurerm_storage_account.main.primary_access_key
  container_app_environment_id = azurerm_container_app_environment.main.id
  share_name                   = azurerm_storage_share.logs.name
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app_environment_storage" "extensions" {
  name                         = "sonarqube-extensions"
  account_name                 = azurerm_storage_account.main.name
  access_key                   = azurerm_storage_account.main.primary_access_key
  container_app_environment_id = azurerm_container_app_environment.main.id
  share_name                   = azurerm_storage_share.extensions.name
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app" "sonarqube" {
  name                         = "sonarqube"
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id

  revision_mode = "Single"

  workload_profile_name = "E8"

  ingress {
    external_enabled = true
    target_port      = 9000
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "sonarqube"
      image  = "sonarqube:lts"
      cpu    = "4"
      memory = "16Gi"

      volume_mounts {
        name = "data"
        path = "/opt/sonarqube/data"
      }
      volume_mounts {
        name = "logs"
        path = "/opt/sonarqube/logs"
      }
      volume_mounts {
        name = "extensions"
        path = "/opt/sonarqube/extensions"
      }

      env {
        name  = "SONAR_JDBC_URL"
        value = "jdbc:postgresql://<your-postgres-server>:5432/sonarqube"
      }
      env {
        name  = "SONAR_JDBC_USERNAME"
        value = "<your-db-username>"
      }
      env {
        name  = "SONAR_JDBC_PASSWORD"
        value = "<your-db-password>"
      }
    }

    volume {
      name          = "data"
      storage_type  = "AzureFile"
      storage_name  = azurerm_container_app_environment_storage.data.name
      mount_options = "dir_mode=0777,file_mode=0777,uid=1000,gid=1000,mfsymlinks,cache=strict,nosharesock"
    }
    volume {
      name          = "logs"
      storage_type  = "AzureFile"
      storage_name  = azurerm_container_app_environment_storage.logs.name
      mount_options = "dir_mode=0777,file_mode=0777,uid=1000,gid=1000,mfsymlinks,cache=strict,nosharesock"
    }
    volume {
      name          = "extensions"
      storage_type  = "AzureFile"
      storage_name  = azurerm_container_app_environment_storage.extensions.name
      mount_options = "dir_mode=0777,file_mode=0777,uid=1000,gid=1000,mfsymlinks,cache=strict,nosharesock"
    }
  }
}
