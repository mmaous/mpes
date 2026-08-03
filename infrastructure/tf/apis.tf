locals {
  gcp_apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "gkehub.googleapis.com",
    "anthos.googleapis.com",
    "mesh.googleapis.com"
  ]
}

resource "google_project_service" "enabled_apis" {
  for_each           = toset(local.gcp_apis)
  project            = var.gcp_project_id
  service            = each.value
  disable_on_destroy = false
}
