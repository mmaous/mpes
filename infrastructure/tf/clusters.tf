resource "google_container_cluster" "primary" {
  name     = local.cluster_primary_name
  location = var.region_primary

  enable_autopilot = true

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.primary.id

  # Maps to the secondary ranges defined in network.tf
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Ensure you can destroy this environment cleanly
  deletion_protection = false

  resource_labels = local.common_labels
}

resource "google_container_cluster" "secondary" {
  name     = local.cluster_secondary_name
  location = var.region_secondary

  enable_autopilot = true

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.secondary.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  deletion_protection = false

  resource_labels = local.common_labels
}
