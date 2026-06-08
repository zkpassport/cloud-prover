terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Remote state in GCS. The bucket must exist before `terraform init`.
  # Create it once with:
  #   gsutil mb -p zkpassport-cloud-prover -l us-central1 gs://zkpassport-cloud-prover-tfstate
  #   gsutil versioning set on gs://zkpassport-cloud-prover-tfstate
  backend "gcs" {
    bucket = "zkpassport-cloud-prover-tfstate"
    prefix = "cloud-prover/gke"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
