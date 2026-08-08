resource "google_compute_address" "gateway_ip" {
  name   = "${local.prefix}-gateway-ip"
  region = var.region_primary
}

resource "google_service_account" "cert_manager_dns" {
  account_id   = "${local.prefix}-cert-manager-dns"
  display_name = "cert-manager DNS-01 solver (${var.environment})"
}

resource "google_project_iam_member" "cert_manager_dns_admin" {
  project = var.gcp_project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.cert_manager_dns.email}"
}

resource "google_service_account_iam_member" "cert_manager_wi_binding" {
  service_account_id = google_service_account.cert_manager_dns.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "serviceAccount:${var.gcp_project_id}.svc.id.goog[cert-manager/cert-manager]"
}
