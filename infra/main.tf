# Container Registry
resource "google_artifact_registry_repository" "instaclause-repo" {
  location      = "us-central1"
  repository_id = "instaclause-repository"
  description   = "instaclause docker repository"
  format        = "DOCKER"
}

# CI/CD Service Account Creation
resource "google_service_account" "cicd_account" {
  account_id   = "instaclause-cicd"
  display_name = "CI/CD Account for Artifact Registry"
}

# CI/CD IAM Binding
resource "google_project_iam_member" "artifact_registry_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cicd_account.email}"
}

# Create a secret in Secrets Manager to store credentials
resource "google_secret_manager_secret" "db_credentials" {
  secret_id = "instaclause-db-credentials"
  replication {
    user_managed {
      replicas {
        location = "us-central1"
      }
      replicas {
        location = "us-east1"
      }
    }
  }
}

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!@#$%^&*"
}

resource "google_secret_manager_secret_version" "db_credentials_version" {
  secret      = google_secret_manager_secret.db_credentials.id
  secret_data = random_password.db_password.result
}


resource "google_sql_database_instance" "dev_database" {
  name             = "instaclause-dev-database"
  database_version = "POSTGRES_15"
  region           = "us-central1"
  root_password    = google_secret_manager_secret_version.db_credentials_version.secret_data
  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled = true
    }
  }
}

locals {
  rev_name_live   = "instaclause-expert-api-service-${var.expert_api_live_version}-live"
  rev_name_canary = "instaclause-expert-api-service-${var.expert_api_canary_version}-canary"
  live_image      = "us-central1-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.instaclause-repo.repository_id}/instaclause-expert-api:${var.expert_api_live_version}"
  canary_image    = "us-central1-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.instaclause-repo.repository_id}/instaclause-expert-api:${var.expert_api_canary_version}"
  canary_percent  = 10
}

resource "google_cloud_run_v2_service" "expert_api" {
  name     = "instaclause-expert-api-service"
  location = "us-central1"

  traffic {
    type = "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"
    # live serves 100% by default. If canary is enabled, this traffic block controls canary
    percent = var.canary_enabled ? local.canary_percent : 100
    # revision is named live by default. When canary is enabled, a new revision named canary is deployed
    revision = var.canary_enabled ? local.rev_name_canary : local.rev_name_live
  }

  dynamic "traffic" {
    # if canary is enabled, add another traffic block
    for_each = var.canary_enabled ? ["canary"] : []
    content {
      type = "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"
      # current live's traffic is now controlled here
      percent  = var.canary_enabled ? 100 - local.canary_percent : 0
      revision = var.canary_enabled ? local.rev_name_live : local.rev_name_canary
    }
  }

  template {
    scaling {
      min_instance_count = 1
      max_instance_count = 2
    }

    containers {
      # if canary is enabled, deploy a canary image
      image = var.canary_enabled ? local.canary_image : local.live_image
      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      ports {
        container_port = 8080
      }
      startup_probe {
        http_get {
          path = "/swagger/index.html"
          port = 8080
        }
        initial_delay_seconds = 60
      }
      resources {
        cpu_idle = true
      }
      env {
        name  = "ASPNETCORE_ENVIRONMENT"
        value = "Development"
      }
      env {
        name  = "ASPNETCORE_URLS"
        value = "http://+:8080"
      }
      # TODO: Find a better way to apply migrations
      env {
        name  = "MigrateDatabase"
        value = "true"
      }
      env {
        name  = "ConnectionStrings__DefaultConnection"
        value = "Host=/cloudsql/instaclause-dev-422515:us-central1:instaclause-dev-database;Database=instaclause;Username=postgres;Password=${google_secret_manager_secret_version.db_credentials_version.secret_data}"
      }
    }
    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.dev_database.connection_name]
      }
    }
  }

}

resource "google_cloud_run_service_iam_binding" "default" {
  location = google_cloud_run_v2_service.expert_api.location
  service  = google_cloud_run_v2_service.expert_api.name
  role     = "roles/run.invoker"
  members = [
    "allUsers"
  ]
}

output "registry_url" {
  value = google_sql_database_instance.dev_database.private_ip_address
}
