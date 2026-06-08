#!/usr/bin/env bash
#
# One-time bootstrap for the cloud-prover GKE deployment in project
# zkpassport-cloud-prover. Creates everything the GitHub Actions deploy needs:
# the Terraform state bucket, then (via Terraform) the GKE cluster, spot node
# pool, static ingress IP, deployer IAM role, log-based metrics and dashboard.
#
# Safe to re-run: the bucket step is idempotent and `terraform apply` only
# changes drift. Requires: gcloud (authenticated as a project Owner/Editor),
# gsutil, terraform. Run from anywhere — paths are resolved relative to this file.
#
# Usage: deploy/bootstrap.sh
set -euo pipefail

PROJECT="zkpassport-cloud-prover"
REGION="us-central1"
ZONE="us-central1-a"
STATE_BUCKET="gs://${PROJECT}-tfstate"
HOSTNAME="cloud-prover.zkpassport.id"

cd "$(dirname "$0")"

echo "==> 1/3  Terraform state bucket (${STATE_BUCKET})"
if gsutil ls -b "$STATE_BUCKET" >/dev/null 2>&1; then
  echo "    already exists"
else
  gsutil mb -p "$PROJECT" -l "$REGION" "$STATE_BUCKET"
fi
gsutil versioning set on "$STATE_BUCKET"

echo "==> 2/3  Provision infra (cluster, spot pool, ingress IP, IAM, metrics, dashboard)"
cd terraform
terraform init
terraform apply

echo "==> 3/3  Next steps"
IP="$(terraform output -raw ingress_ip)"
cat <<EOF

  Ingress IP: ${IP}

  1. Create the DNS A record:
         ${HOSTNAME}  A  ${IP}

  2. Deploy: merge to main (GitHub Actions builds + deploys), or manually:
         gcloud container clusters get-credentials cloud-prover --zone ${ZONE} --project ${PROJECT}
         kubectl apply -k ../k8s/base

  3. Wait for the managed TLS cert to go Active (15-60 min after DNS resolves):
         kubectl -n zkpassport-cloud-prover describe managedcertificate cloud-prover | grep -i status

  4. After the GKE endpoint is verified serving proofs, decommission Cloud Run:
         gcloud run services delete gcloud-prover --project=${PROJECT} --region=${REGION}
EOF
