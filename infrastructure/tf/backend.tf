terraform {
  backend "gcs" {
    bucket = "mpes-terraform-state"
    prefix = "terraform/state"
  }
}
