variable "project_id" {
  description = "GCP project ID where n8n will be deployed."
  type        = string
}

variable "region" {
  description = "GCP region for Cloud Run and Cloud SQL."
  type        = string
  default     = "us-south1"
}

variable "service_name" {
  description = "Cloud Run service name. Lowercase letters, numbers, and hyphens only."
  type        = string
  default     = "n8n"

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.service_name))
    error_message = "service_name must start with a lowercase letter, end with a lowercase letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "n8n_image" {
  description = "n8n container image."
  type        = string
  default     = "docker.io/n8nio/n8n:latest"
}

variable "timezone" {
  description = "Timezone used by n8n."
  type        = string
  default     = "America/Chicago"
}

variable "min_instances" {
  description = "Minimum Cloud Run instances. 0 for scale-to-zero, 1 for always-on."
  type        = number
  default     = 0

  validation {
    condition     = var.min_instances >= 0
    error_message = "min_instances must be 0 or greater."
  }
}

variable "max_instances" {
  description = "Maximum Cloud Run instances."
  type        = number
  default     = 3

  validation {
    condition     = var.max_instances >= 1
    error_message = "max_instances must be 1 or greater."
  }
}

variable "cpu" {
  description = "Cloud Run CPU limit."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Cloud Run memory limit."
  type        = string
  default     = "2Gi"
}

variable "database_tier" {
  description = "Cloud SQL machine tier. db-f1-micro is low cost and suitable for testing."
  type        = string
  default     = "db-f1-micro"
}

variable "database_disk_size" {
  description = "Cloud SQL disk size in GB."
  type        = number
  default     = 10
}

variable "database_backups_enabled" {
  description = "Enable automated Cloud SQL backups."
  type        = bool
  default     = true
}

variable "database_name" {
  description = "PostgreSQL database name for n8n."
  type        = string
  default     = "n8n"
}

variable "database_user" {
  description = "PostgreSQL user for n8n."
  type        = string
  default     = "n8n_user"
}
