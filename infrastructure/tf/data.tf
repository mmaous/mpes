data "google_client_config" "default" {}

data "http" "my_ip" {
  url = "https://ipv4.icanhazip.com"
}
