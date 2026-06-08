variable "project_id" {
  type    = string
  default = "zkpassport-cloud-prover"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type        = string
  default     = "us-central1-a"
  description = "Zonal cluster (single zone) to keep cost down, mirroring the aztec GKE setup."
}

variable "cluster_name" {
  type    = string
  default = "cloud-prover"
}

# --- Prover (spot) node pool ---------------------------------------------

variable "prover_machine_type" {
  type        = string
  default     = "t2d-standard-16"
  description = "16 vCPU / 64 GB. One proof per node; ~84s per large EVM outer proof."
}

variable "prover_min_nodes" {
  type        = number
  default     = 1
  description = "Warm capacity. 1 = always one spot node ready (no cold start)."
}

variable "prover_max_nodes" {
  type        = number
  default     = 6
  description = "Burst ceiling. Cluster autoscaler adds spot nodes as pending proof pods appear."
}

# --- System node pool (small, on-demand) ---------------------------------

variable "system_machine_type" {
  type        = string
  default     = "e2-medium"
  description = "Hosts GKE system pods (kube-dns etc.) so they don't churn on spot eviction."
}

# --- Deployer service account (already exists; created for the Cloud Run CI) ---

variable "deployer_sa_email" {
  type    = string
  default = "github-actions-deployer@zkpassport-cloud-prover.iam.gserviceaccount.com"
}
