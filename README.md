# ZKPassport Cloud Prover

**NOTE:** This cloud prover is only used for recursing sub-proofs (already proven with concealed private inputs) into a final compressed EVM-compatible proof, or for proving non-sensitive sub-proofs, where a user's device memory is insufficient (i.e. less than ~2 GB). No sensitive passport/national ID card information ever leaves a user's device (unless they explicitly share it with a service).

A cloud-based prover service for generating proofs using Barretenberg (bb), deployed on **GKE** (spot nodes).

## Description

This project implements a cloud prover service for ZKPassport, built using Node.js and TypeScript. It
runs as a containerized service on GKE and shells out to the Barretenberg (bb) proving system.
The container bundles pinned bb builds (`4.2.0-aztecnr-rc.2` and `5.0.0`) plus the CRS, and
exposes a single `POST /prove` endpoint. The `bb_version` field in the request body selects
which build to use. Only the `outer*`, `facematch*`, and `sig_check_dsc*`
circuits are accepted (validated against the ZKPassport circuit registry).

## Architecture

- **Compute:** GKE Standard cluster `cloud-prover` in `us-central1-a`, project `zkpassport-cloud-prover`.
  A small on-demand **system** node pool plus a **spot `t2d-standard-16`** pool (16 vCPU / 64 GB) that
  runs the prover — one proof per node, ~84 s per large EVM outer proof. The prover pod requests
  ~14 vCPU / 16 GiB (measured peak ~11 GiB RAM, ~7 cores avg with bursts to all 16). Cluster
  autoscaler scales the spot pool (`min 1` warm node → `max 6`) as proof pods queue.
- **Networking:** GCE Ingress with a Google-managed TLS cert on a static IP; backend timeout 600 s
  (proofs run ~84 s).
- **Image registry:** Artifact Registry `us-central1-docker.pkg.dev/zkpassport-cloud-prover/cloud-prover`.
- **IaC:** `deploy/terraform/` (cluster, node pools, IAM, static IP) and `deploy/k8s/` (kustomize
  manifests). See [`deploy/README.md`](deploy/README.md) for the bootstrap + cutover runbook.
- **CI/CD:** GitHub Actions (`.github/workflows/deploy.yml`) authenticates to GCP via Workload
  Identity Federation, builds the image on Cloud Build (`deploy/cloudbuild.yaml` — bb is fetched as a
  prebuilt binary, so the build is light/fast), then `kubectl apply -k`s the manifests to GKE.
  Triggered manually via `workflow_dispatch` (Actions tab or `gh workflow run`).

## Prerequisites

- Node.js 20+
- Docker (for local image builds)
- `gcloud` CLI (for manual deploys / inspection)

## Local Development

Run the server directly against locally-installed bb binaries:

```sh
npm install
npm run dev   # ts-node src/server.ts, expects bb on PATH (see BB_VERSIONS in src/handler.ts)
```

Or build and run the full container image (linux/amd64):

```sh
docker buildx build --platform linux/amd64 -t cloud-prover .
docker run --platform linux/amd64 -p 3000:3000 --rm -it cloud-prover
```

This gives a local `http://localhost:3000` endpoint with `POST /prove`.

## Deployment

Deploys are triggered manually — run the **Deploy to GKE** workflow from the Actions tab
(or `gh workflow run "Deploy to GKE"`). For first-time cluster provisioning, manual deploys,
and decommissioning the old Cloud Run service, see [`deploy/README.md`](deploy/README.md).
Manual image build + deploy:

```sh
# Build + push image on Cloud Build
gcloud builds submit --project=zkpassport-cloud-prover --config=deploy/cloudbuild.yaml \
  --substitutions=_SHA=$(git rev-parse --short HEAD)

# Deploy to GKE
gcloud container clusters get-credentials cloud-prover --zone us-central1-a --project zkpassport-cloud-prover
cd deploy/k8s/base
kustomize edit set image \
  us-central1-docker.pkg.dev/zkpassport-cloud-prover/cloud-prover/cloud-prover=us-central1-docker.pkg.dev/zkpassport-cloud-prover/cloud-prover/cloud-prover:$(git rev-parse --short HEAD)
kubectl apply -k .
```

## Test

```sh
bun test
```
