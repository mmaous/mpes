locals {
  prefix = "${var.project_slug}-${var.environment}"

  region_short_map = {
    (var.region_primary)   = "use1"
    (var.region_secondary) = "euw1"
  }

  cluster_primary_name   = "${local.prefix}-${local.region_short_map[var.region_primary]}-gke-primary"
  cluster_secondary_name = "${local.prefix}-${local.region_short_map[var.region_secondary]}-gke-secondary"

  vpc_name              = "${local.prefix}-vpc"
  subnet_primary_name   = "${local.prefix}-${local.region_short_map[var.region_primary]}-snet-gke"
  subnet_secondary_name = "${local.prefix}-${local.region_short_map[var.region_secondary]}-snet-gke"

  common_labels = {
    project     = var.project_slug
    environment = var.environment
    managed_by  = "terraform"
    owner       = "platform-team"
  }
}
