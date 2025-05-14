variable "project_id" {
    type = string
    description = "The ID of the GCP project"
}

variable "region" {
    type = string
    description = "The region to deploy the Cloud Run service to"
    default = "us-west1"
}

variable "container_name" {
    description = "Full container image URL"
    type = string
    
}

variable "custom_domain" {
    description = "Custom domain name"
    type = string
    default = "zkpassport-cloud-prover.aztec.network"
}