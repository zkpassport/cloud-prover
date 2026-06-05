# ZKPassport Cloud Prover

**NOTE:** This cloud prover is only used for recursing sub-proofs (already proven with concealed private inputs) into a final compressed EVM-compatible proof, or for proving non-sensitive sub-proofs, where a user's device memory is insufficient (i.e. less than ~2 GB). No sensitive passport/national ID card information ever leaves a user's device (unless they explicitly share it with a service).

A cloud-based prover service for generating proofs using Barretenberg (bb), deployed on **Google Cloud Run**.

## Description

This project implements a cloud prover service for ZKPassport, built using Node.js and TypeScript. It
runs as a containerized service on Cloud Run and shells out to the Barretenberg (bb) proving system.
The container bundles two pinned bb builds (`2.0.3` and `4.2.0-aztecnr-rc.2`) plus the CRS, and
exposes a single `POST /prove` endpoint. Only the `outer*`, `facematch*`, and `sig_check_dsc*`
circuits are accepted (validated against the ZKPassport circuit registry).

## Architecture

- **Compute:** Cloud Run service `gcloud-prover` in `us-central1`, project `zkpassport-cloud-prover`.
  Sized at 8 vCPU / 8 GiB, `concurrency=1` (one proof per instance), `min-instances=1` (warm, to
  avoid cold starts) and `max-instances=15` for bursts. Request-based billing (pay per proof).
- **Image registry:** Artifact Registry `us-central1-docker.pkg.dev/zkpassport-cloud-prover/cloud-prover`.
- **CI/CD:** GitHub Actions (`.github/workflows/deploy.yml`) authenticates to GCP via Workload
  Identity Federation, builds the image on a high-CPU Cloud Build machine (`cloudbuild.yaml` — bb is
  compiled from source, too heavy for default runners), then deploys to Cloud Run. Triggered on push
  to `main` or manually via `workflow_dispatch`.

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
docker run --platform linux/amd64 -p 8080:8080 --rm -it cloud-prover
```

This gives a local `http://localhost:8080` endpoint with `POST /prove`.

## Deployment

Deploys run automatically via GitHub Actions on push to `main`. To deploy manually:

```sh
# Build + push image on Cloud Build
gcloud builds submit --project=zkpassport-cloud-prover --config=cloudbuild.yaml \
  --substitutions=_SHA=$(git rev-parse --short HEAD)

# Deploy the new image to Cloud Run
gcloud run deploy gcloud-prover --project=zkpassport-cloud-prover --region=us-central1 \
  --image=us-central1-docker.pkg.dev/zkpassport-cloud-prover/cloud-prover/cloud-prover:$(git rev-parse --short HEAD) \
  --cpu=8 --memory=8Gi --concurrency=1 --min-instances=1 --max-instances=15 \
  --timeout=3600 --execution-environment=gen2 --cpu-boost --allow-unauthenticated
```

## Test

```sh
bun test
```
