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
  value       = "gcloud container clusters get-credentials ${google_container_cluster.secondary.name} --zone ${var.zone_secondary} --project ${var.gcp_project_id}"
}

output "project_id" {
  value = google_container_cluster.primary.project
}

output "primary_location" {
  value = google_container_cluster.primary.location
}

output "secondary_location" {
  value = google_container_cluster.secondary.location
}

output "secondary_private_endpoint" {
  value = google_container_cluster.secondary.private_cluster_config[0].private_endpoint
}

output "eso_gsa_email" {
  value = google_service_account.eso_gsa.email
}

output "gateway_static_ip" {
  value = google_compute_address.gateway_ip.address
}

output "cert_manager_dns_sa_email" {
  value = google_service_account.cert_manager_dns.email
}

output "nat_primary_ip" {
  value = google_compute_address.nat_primary_ip.address
}

