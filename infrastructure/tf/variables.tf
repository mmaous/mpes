variable "gcp_project_id" {
  description = "The GCP Project ID where resources will be deployed"
  type        = string
}

variable "project_slug" {
  description = "A short name for the project to prefix resources (e.g., mpes)"
  type        = string
  default     = "mpes"
}

variable "environment" {
  description = "The environment context (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

variable "region_primary" {
  description = "The primary region for cluster A"
  type        = string
  default     = "us-central1"
}

variable "region_secondary" {
  description = "The secondary region for cluster B"
  type        = string
  default     = "europe-west1"
}
