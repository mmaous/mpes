# Dedicated minimal-permission SA for GKE nodes — replaces the default
# Compute Engine SA, which carries broad legacy Editor-like permissions.
# Fine-grained pod-level access should go through Workload Identity instead
# of broadening this SA's roles.
resource "google_service_account" "gke_nodes" {
  account_id   = "${local.prefix}-gke-nodes"
  display_name = "GKE Node Service Account (${var.environment})"
}

resource "google_project_iam_member" "gke_nodes_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ])
  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}
