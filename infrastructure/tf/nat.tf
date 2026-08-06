resource "google_compute_router" "router_primary" {
  name    = "${local.prefix}-${local.region_short_map[var.region_primary]}-router"
  region  = var.region_primary
  network = google_compute_network.vpc.id
}

resource "google_compute_address" "nat_primary_ip" {
  name   = "${local.prefix}-${local.region_short_map[var.region_primary]}-nat-ip"
  region = var.region_primary
}

resource "google_compute_router_nat" "nat_primary" {
  name                               = "${local.prefix}-${local.region_short_map[var.region_primary]}-nat"
  router                             = google_compute_router.router_primary.name
  region                             = google_compute_router.router_primary.region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.nat_primary_ip.self_link]
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_router" "router_secondary" {
  name    = "${local.prefix}-${local.region_short_map[var.region_secondary]}-router"
  region  = var.region_secondary
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat_secondary" {
  name                               = "${local.prefix}-${local.region_short_map[var.region_secondary]}-nat"
  router                             = google_compute_router.router_secondary.name
  region                             = google_compute_router.router_secondary.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
