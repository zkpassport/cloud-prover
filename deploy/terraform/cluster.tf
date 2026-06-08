# Standard zonal GKE cluster: a small on-demand system pool for GKE system
# workloads + a spot pool that runs the prover.
resource "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.zone
  project  = var.project_id

  # We manage node pools explicitly below, so drop the default one.
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Monitoring is via Cloud Logging (structured proof logs) + the log-based
  # metric in monitoring.tf — no Prometheus scraping needed.

  deletion_protection = true

  depends_on = [google_project_service.container]
}

# Small, on-demand pool for GKE system workloads (kube-dns, metrics, GMP).
# Keeps the control-plane-adjacent pods stable even when spot nodes are reclaimed.
resource "google_container_node_pool" "system" {
  name       = "system"
  cluster    = google_container_cluster.this.id
  node_count = 1

  node_config {
    machine_type = var.system_machine_type
    disk_size_gb = 50
    disk_type    = "pd-balanced"

    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = { pool = "system" }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# Spot pool that runs the prover. One proof per node (the pod requests ~14 vCPU).
# Tainted so ONLY prover pods land on these (more expensive, evictable) nodes.
resource "google_container_node_pool" "prover_spot" {
  name    = "prover-spot"
  cluster = google_container_cluster.this.id

  autoscaling {
    min_node_count = var.prover_min_nodes
    max_node_count = var.prover_max_nodes
  }

  node_config {
    machine_type = var.prover_machine_type
    spot         = true
    disk_size_gb = 100
    disk_type    = "pd-balanced"

    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = { pool = "prover" }

    taint {
      key    = "dedicated"
      value  = "prover"
      effect = "NO_SCHEDULE"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
