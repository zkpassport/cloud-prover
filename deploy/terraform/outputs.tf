output "cluster_name" {
  value = google_container_cluster.this.name
}

output "cluster_location" {
  value = google_container_cluster.this.location
}

output "ingress_ip" {
  description = "Point the prover DNS A record (e.g. cloud-prover.zkpassport.id) at this address."
  value       = google_compute_global_address.ingress.address
}

output "get_credentials_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --zone ${google_container_cluster.this.location} --project ${var.project_id}"
}
