locals {
  # Base prefixes
  prefix = "${var.project_slug}-${var.environment}"

  # Standardized region short-names for resources (e.g., us-central1 -> usc1)
  region_short_map = {
    (var.region_primary)   = "usc1"
    (var.region_secondary) = "euw1"
  }

  # Cluster Names
  cluster_primary_name   = "${local.prefix}-${local.region_short_map[var.region_primary]}-gke-primary"
  cluster_secondary_name = "${local.prefix}-${local.region_short_map[var.region_secondary]}-gke-secondary"

  # VPC and Subnet Names
  vpc_name              = "${local.prefix}-vpc"
  subnet_primary_name   = "${local.prefix}-${local.region_short_map[var.region_primary]}-snet-gke"
  subnet_secondary_name = "${local.prefix}-${local.region_short_map[var.region_secondary]}-snet-gke"

  # mandatory Labels (Applied to ALL resources)
  common_labels = {
    project     = var.project_slug
    environment = var.environment
    managed_by  = "terraform"
    owner       = "platform-team"
  }
}
