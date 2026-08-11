data "google_client_config" "default" {}

data "http" "my_ip" {
  url = "https://ipv4.icanhazip.com"
}

data "google_dns_managed_zone" "mmlabs" {
  name = "labs"
}

locals {
  app_subdomains = ["kubecounter"]
}
