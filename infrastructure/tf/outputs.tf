output "primary_cluster_name" {
  description = "The name of the US-Central cluster"
  value       = google_container_cluster.primary.name
}

output "secondary_cluster_name" {
  description = "The name of the Europe-West cluster"
  value       = google_container_cluster.secondary.name
}

output "connect_to_primary_command" {
  description = "Run this in your terminal to authenticate kubectl to Cluster A"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region_primary} --project ${var.gcp_project_id}"
}

output "connect_to_secondary_command" {
  description = "Run this in your terminal to authenticate kubectl to Cluster B"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.secondary.name} --region ${var.region_secondary} --project ${var.gcp_project_id}"
}
