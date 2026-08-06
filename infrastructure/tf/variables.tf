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
  default     = "us-east1"
}

variable "region_secondary" {
  description = "The secondary region for cluster B"
  type        = string
  default     = "europe-west1"
}

variable "primary_zones" {
  description = "Zones for primary regional cluster's node pool (regional control plane spans these automatically)"
  type        = list(string)
  default     = ["us-east1-b", "us-east1-c", "us-east1-d"]
}

variable "zone_secondary" {
  description = "Single zone for secondary zonal cluster (closest GKE analog to a single control-plane topology)"
  type        = string
  default     = "europe-west1-b"
}
