# Deploying the cloud prover (GKE)

The prover runs on **GKE Standard** in project `zkpassport-cloud-prover` (`us-central1-a`):
a small on-demand **system** node pool plus a **spot `t2d-standard-16`** pool that runs the
prover (16 vCPU / 64 GB, ~84s per large EVM outer proof, one proof per node).

- `terraform/` — cluster, node pools, static ingress IP, deployer IAM.
- `k8s/base/` — Deployment, Services, HPA, BackendConfig (600s timeout), ManagedCertificate, Ingress.
- CI: `.github/workflows/deploy.yml` builds the image on Cloud Build and `kubectl apply -k`s the manifests.

## One-time bootstrap

```sh
# 1. Terraform state bucket
gsutil mb -p zkpassport-cloud-prover -l us-central1 gs://zkpassport-cloud-prover-tfstate
gsutil versioning set on gs://zkpassport-cloud-prover-tfstate

# 2. Cluster + node pools + static IP + deployer IAM
cd deploy/terraform
terraform init
terraform apply          # enables the GKE API, then builds everything
terraform output ingress_ip   # -> set the DNS A record below

# 3. DNS: point the prover hostname at the ingress IP
#    cloud-prover.zkpassport.id  A  <ingress_ip>
#    (also update the domain in k8s/base/managedcertificate.yaml + ingress if different)

# 4. First app deploy (CI does this on every push to main thereafter)
cd ../k8s/base
gcloud container clusters get-credentials cloud-prover --zone us-central1-a --project zkpassport-cloud-prover
kubectl apply -k .

# 5. Wait for the managed cert to go Active (can take 15-60 min after DNS resolves)
kubectl -n zkpassport-cloud-prover describe managedcertificate cloud-prover
```

## Decommission the old Cloud Run service

Once the GKE endpoint serves proofs and the mobile app/SDK points at the new host:

```sh
gcloud run services delete gcloud-prover --project=zkpassport-cloud-prover --region=us-central1
```

## Monitoring

No Prometheus — observability is via the **standard Google Cloud console**:

- **Per-proof timing (Cloud Logging → Logs Explorer):** the handler emits one structured JSON line
  per proof. Query:
  ```
  resource.type="k8s_container"
  jsonPayload.event="proof_generated"
  ```
  Fields: `total_ms`, `bb_prove_ms`, `witness_gen_ms`, `witness_source`, `circuit_name`, `bb_version`,
  `evm`, `disable_zk`. Failures log `jsonPayload.event="proof_failed"`.
- **In-bb step breakdown (CRS load / proving-key build / proving):** bb's `-v` output is logged with
  a `[bb_verbose]` prefix on each proof — search `"[bb_verbose]"`.
- **Dashboard (Cloud Monitoring):** `monitoring.tf` creates a **"Cloud Prover"** dashboard with proof
  duration p50/p95, the witness_gen / bb_prove / total step breakdown, median time per circuit,
  throughput, and a logs panel of recent per-proof splits. It's built on log-based distribution
  metrics `cloud_prover/proof_{total,bb_prove,witness_gen}_ms` (+ `proof_count`), labelled by
  `circuit_name` and `evm` — also usable directly in Metrics Explorer and for alerts.
- **CPU / memory:** GKE reports container resource usage to Cloud Monitoring natively — no extra setup.

> The dashboard widget JSON is best-effort; if a chart looks off after `terraform apply`, tweak it in
> the console (it's the standard Monitoring dashboard) — the underlying metrics are the durable part.

## Notes / known limitations

- **Spot eviction**: a reclaimed node kills the in-flight proof; the client must retry.
  `terminationGracePeriodSeconds: 120` lets a near-complete proof finish on graceful drains.
- **Scaling signal**: HPA scales on CPU (60%), a coarse proxy for "a proof is running" — same as
  the previous setup. True one-proof-per-pod admission would need an app-level concurrency gate or
  a custom request-count metric.
- **Cost (spot, us-central1, approx)**: warm baseline ≈ system `e2-medium` (~$24/mo) +
  one `t2d-standard-16` spot node (~$131/mo). Additional spot nodes only while bursting.
