provider "azurerm" {
  features {}
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
    name                  = "default"
    workload_profile_type = "E4"
    maximum_count         = 1
  }

  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
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
  container_app_environment_id = azurerm_container_app_environment.main.id
  share_name                   = azurerm_storage_share.data.name
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app_environment_storage" "logs" {
  name                         = "sonarqube-logs"
  container_app_environment_id = azurerm_container_app_environment.main.id
  share_name                   = azurerm_storage_share.logs.name
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app_environment_storage" "extensions" {
  name                         = "sonarqube-extensions"
  container_app_environment_id = azurerm_container_app_environment.main.id
  share_name                   = azurerm_storage_share.extensions.name
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app" "sonarqube" {
  name                         = "sonarqube"
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id

  revision_mode = "Single"

  ingress {
    external_enabled = true
    target_port      = 9000
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    container {
      name   = "sonarqube"
      image  = "sonarqube:9.9.8-community"
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

      # env {
      #   name  = "SONAR_JDBC_URL"
      #   value = "jdbc:postgresql://<your-postgres-server>:5432/sonarqube"
      # }
      # env {
      #   name  = "SONAR_JDBC_USERNAME"
      #   value = "<your-db-username>"
      # }
      # env {
      #   name  = "SONAR_JDBC_PASSWORD"
      #   value = "<your-db-password>"
      # }
    }

    volume {
      name         = "data"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.data.name
    }
    volume {
      name         = "logs"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.logs.name
    }
    volume {
      name         = "extensions"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.extensions.name
    }
  }
}
