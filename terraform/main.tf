terraform {
  required_version = ">= 1.6.0"

  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  required_apis = toset([
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "sqladmin.googleapis.com",
  ])

  cloud_run_sa_id = trimsuffix(substr("${var.service_name}-run", 0, 30), "-")

  n8n_env = {
    DB_POSTGRESDB_DATABASE                = var.database_name
    DB_POSTGRESDB_HOST                    = "/cloudsql/${google_sql_database_instance.n8n.connection_name}"
    DB_POSTGRESDB_PORT                    = "5432"
    DB_POSTGRESDB_SCHEMA                  = "public"
    DB_POSTGRESDB_USER                    = var.database_user
    DB_TYPE                               = "postgresdb"
    EXECUTIONS_MODE                       = "regular"
    GENERIC_TIMEZONE                      = var.timezone
    N8N_DIAGNOSTICS_ENABLED               = "false"
    N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = "true"
    N8N_ENDPOINT_HEALTH                   = "health"
    N8N_PORT                              = "5678"
    N8N_PROTOCOL                          = "https"
    N8N_RUNNERS_ENABLED                   = "true"
    TZ                                    = var.timezone
  }
}

# ---------------------------------------------------------------------------
# APIs
# ---------------------------------------------------------------------------

resource "google_project_service" "required" {
  for_each = local.required_apis

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

resource "google_service_account" "cloud_run" {
  project      = var.project_id
  account_id   = local.cloud_run_sa_id
  display_name = "n8n Cloud Run runtime service account"

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "cloud_run_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------

resource "random_password" "db_password" {
  length  = 32
  special = false
}

resource "random_password" "n8n_encryption_key" {
  length  = 64
  special = false
}

resource "google_secret_manager_secret" "db_password" {
  project   = var.project_id
  secret_id = "${var.service_name}-db-password"

  replication {
    auto {}
  }

  labels = {
    app = "n8n"
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

resource "google_secret_manager_secret" "n8n_encryption_key" {
  project   = var.project_id
  secret_id = "${var.service_name}-encryption-key"

  replication {
    auto {}
  }

  labels = {
    app = "n8n"
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "n8n_encryption_key" {
  secret      = google_secret_manager_secret.n8n_encryption_key.id
  secret_data = random_password.n8n_encryption_key.result
}

resource "google_secret_manager_secret_iam_member" "cloud_run_db_password" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run.email}"
}

resource "google_secret_manager_secret_iam_member" "cloud_run_encryption_key" {
  secret_id = google_secret_manager_secret.n8n_encryption_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run.email}"
}

# ---------------------------------------------------------------------------
# Cloud SQL
# ---------------------------------------------------------------------------

resource "google_sql_database_instance" "n8n" {
  project          = var.project_id
  name             = "${var.service_name}-db"
  region           = var.region
  database_version = "POSTGRES_15"

  deletion_protection = false

  settings {
    tier              = var.database_tier
    availability_type = "ZONAL"
    disk_size         = var.database_disk_size
    disk_type         = "PD_HDD"
    disk_autoresize   = true

    backup_configuration {
      enabled    = var.database_backups_enabled
      start_time = "09:00"
    }

    ip_configuration {
      ipv4_enabled = true
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_sql_database" "n8n" {
  project  = var.project_id
  name     = var.database_name
  instance = google_sql_database_instance.n8n.name
}

resource "google_sql_user" "n8n" {
  project  = var.project_id
  name     = var.database_user
  instance = google_sql_database_instance.n8n.name
  password = random_password.db_password.result
}

# ---------------------------------------------------------------------------
# Cloud Run
# ---------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "n8n" {
  project  = var.project_id
  name     = var.service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  deletion_protection = false

  labels = {
    app = "n8n"
  }

  template {
    service_account                  = google_service_account.cloud_run.email
    timeout                          = "300s"
    max_instance_request_concurrency = 80

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    volumes {
      name = "cloudsql"

      cloud_sql_instance {
        instances = [google_sql_database_instance.n8n.connection_name]
      }
    }

    containers {
      image = var.n8n_image

      ports {
        container_port = 5678
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }

        cpu_idle          = var.min_instances == 0
        startup_cpu_boost = true
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      dynamic "env" {
        for_each = local.n8n_env

        content {
          name  = env.key
          value = env.value
        }
      }

      env {
        name = "DB_POSTGRESDB_PASSWORD"

        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "N8N_ENCRYPTION_KEY"

        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.n8n_encryption_key.secret_id
            version = "latest"
          }
        }
      }

      startup_probe {
        initial_delay_seconds = 20
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 12

        http_get {
          path = "/health"
          port = 5678
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.max_instances >= var.min_instances
      error_message = "max_instances must be greater than or equal to min_instances."
    }
  }

  depends_on = [
    google_project_iam_member.cloud_run_cloudsql_client,
    google_secret_manager_secret_iam_member.cloud_run_db_password,
    google_secret_manager_secret_iam_member.cloud_run_encryption_key,
    google_sql_database.n8n,
    google_sql_user.n8n,
  ]
}

resource "google_cloud_run_service_iam_member" "public_invoker" {
  project  = var.project_id
  location = google_cloud_run_v2_service.n8n.location
  service  = google_cloud_run_v2_service.n8n.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
