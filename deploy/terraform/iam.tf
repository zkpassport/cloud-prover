# The GitHub Actions deployer SA already has the Cloud Run / Artifact Registry /
# Cloud Build roles. To deploy to GKE it additionally needs to fetch cluster
# credentials and apply manifests.
resource "google_project_iam_member" "deployer_container_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${var.deployer_sa_email}"
}
