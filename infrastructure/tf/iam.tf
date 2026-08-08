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


# Create the Google Service Account for External Secrets
resource "google_service_account" "eso_gsa" {
  account_id   = "external-secrets-operator"
  display_name = "External Secrets Operator GSA"
}

# Grant the GSA permission to access Secret Manager payloads
resource "google_project_iam_member" "eso_secret_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.eso_gsa.email}"
}

# Bind the Kubernetes Service Account (KSA) to the Google Service Account (GSA)
# This allows pods in the "external-secrets" namespace to impersonate this GSA safely
resource "google_service_account_iam_member" "eso_workload_identity_binding" {
  service_account_id = google_service_account.eso_gsa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[external-secrets/external-secrets]"
}
