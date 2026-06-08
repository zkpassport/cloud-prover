# Enable the APIs this stack needs. (artifactregistry + cloudbuild are already
# enabled from the existing image-build pipeline; container is not.)
resource "google_project_service" "container" {
  project            = var.project_id
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

# Global static IP for the ingress load balancer, so the DNS A record is stable
# across redeploys. Referenced by the Ingress via the
# `kubernetes.io/ingress.global-static-ip-name` annotation.
resource "google_compute_global_address" "ingress" {
  name    = "${var.cluster_name}-ip"
  project = var.project_id
}
