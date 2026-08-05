resource "google_compute_network" "vpc" {
  name                    = local.vpc_name
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"

  depends_on = [google_project_service.enabled_apis]
}

resource "google_compute_subnetwork" "primary" {
  name                     = local.subnet_primary_name
  region                   = var.region_primary
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.10.0.0/20" # node ips
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.100.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.101.0.0/20"
  }
}

resource "google_compute_subnetwork" "secondary" {
  name                     = local.subnet_secondary_name
  region                   = var.region_secondary
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.20.0.0/20" # node ips
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.200.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.201.0.0/20"
  }
}
