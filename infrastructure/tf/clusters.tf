# PRIMARY — Regional (3-zone HA control plane), private nodes, ~3 workers min
resource "google_container_cluster" "primary" {
  name     = local.cluster_primary_name
  location = var.region_primary

  node_locations           = var.primary_zones
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.primary.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }


  datapath_provider = "ADVANCED_DATAPATH" # GKE Dataplane V2 — required for NetworkPolicy enforcement

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
    master_global_access_config {
      enabled = true
    }
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "${chomp(data.http.my_ip.response_body)}/32"
      display_name = "Terraform Runner IP"
    }
  }

  deletion_protection = false
  resource_labels     = local.common_labels

  depends_on = [google_project_service.enabled_apis]
}

resource "google_container_node_pool" "primary_workers" {
  name           = "${local.cluster_primary_name}-pool"
  cluster        = google_container_cluster.primary.name
  location       = var.region_primary
  node_locations = var.primary_zones

  autoscaling {
    min_node_count = 1 # × 3 zones = 3 total minimum
    max_node_count = 2 # × 3 zones = 6 total ceiling
  }

  node_config {
    machine_type    = "e2-standard-2"
    disk_size_gb    = 30
    disk_type       = "pd-standard"
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/monitoring"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = local.common_labels
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# SECONDARY — Zonal (single-zone control plane), private nodes, ~2 workers min
resource "google_container_cluster" "secondary" {
  name     = local.cluster_secondary_name
  location = var.zone_secondary

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.secondary.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  datapath_provider = "ADVANCED_DATAPATH"

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.16/28"
    master_global_access_config {
      enabled = true
    }
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "${google_compute_address.nat_primary_ip.address}/32"
      display_name = "Argo CD NAT IP"
    }
    cidr_blocks {
      cidr_block   = "${chomp(data.http.my_ip.response_body)}/32"
      display_name = "Terraform Runner IP"
    }
    cidr_blocks {
      cidr_block   = google_compute_subnetwork.primary.ip_cidr_range
      display_name = "Primary Cluster Nodes"
    }
  }

  deletion_protection = false
  resource_labels     = local.common_labels

  depends_on = [google_project_service.enabled_apis]
}

resource "google_container_node_pool" "secondary_workers" {
  name     = "${local.cluster_secondary_name}-pool"
  cluster  = google_container_cluster.secondary.name
  location = var.zone_secondary

  autoscaling {
    min_node_count = 1
    max_node_count = 6
  }

  node_config {
    machine_type    = "e2-medium"
    disk_size_gb    = 30
    disk_type       = "pd-standard"
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/monitoring"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = local.common_labels
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
