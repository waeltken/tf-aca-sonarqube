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
  account_tier             = "Premium"
  account_replication_type = "LRS"
  account_kind             = "FileStorage"
}

resource "azurerm_container_app_environment" "main" {
  name                = "sonarqube-environment"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  workload_profile {
    name                  = "E8"
    workload_profile_type = "E8"
    maximum_count         = 1
  }

  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

resource "azurerm_storage_share" "data" {
  name               = "sonarqube-data"
  storage_account_id = azurerm_storage_account.main.id
  quota              = 100

  enabled_protocol = "NFS"
}

resource "azurerm_storage_share" "logs" {
  name               = "sonarqube-logs"
  storage_account_id = azurerm_storage_account.main.id
  quota              = 100

  enabled_protocol = "NFS"
}

resource "azurerm_storage_share" "extensions" {
  name               = "sonarqube-extensions"
  storage_account_id = azurerm_storage_account.main.id
  quota              = 100

  enabled_protocol = "NFS"
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
