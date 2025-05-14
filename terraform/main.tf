provider "google" {
    project = var.project_id
    region = var.region
}

resource "google_cloud_run_service" "aztec-zkpassport-cloud-prover" {
    name = "zk-prover"
    location = var.region

    template {
        spec {
            containers {
                image = var.container_name
                resources {
                    limits = {
                        memory = "32Gi"
                        cpu = "8"
                    }
                }
            }
            container_concurrency = 1
            // TODO: check
            timeout_seconds = 600
        }
        metadata {
            annotations = {
                "autoscaling.knative.dev/maxScale" = "100"
            }
        }
    }
    traffic {
        percent = 100
        latest_revision = true
    }
}

resource "google_cloud_run_domain_mapping" "zkpassport-domain" {
    location = var.region
    name = var.custom_domain

    metadata {
        namespace = var.project_id
    }

    spec {
        route_name = google_cloud_run_service.aztec-zkpassport-cloud-prover.name
    }
}

resource "google_cloud_run_service_iam_member" "public_invoker" {
    location = google_cloud_run_service.aztec-zkpassport-cloud-prover.location
    project = var.project_id
    service = google_cloud_run_service.aztec-zkpassport-cloud-prover.name

    role = "roles/run.invoker"
    member = "allUsers"
}

