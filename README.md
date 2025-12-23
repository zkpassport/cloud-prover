# ZKPassport Cloud Prover

**NOTE:** This cloud prover is only used for recursing sub-proofs (already proven with concealed private inputs) into a final compressed EVM-compatible proof, or for proving non-sensitive sub-proofs, where a user's device memory is insufficient (i.e. less than ~2 GB). No sensitive passport/national ID card information ever leaves a user's device (unless they explicitly share it with a service).

A cloud-based prover service for generating proofs using Barretenberg (bb), deployed on AWS Fargate
with Application Load Balancer.

## Description

This project implements a cloud prover service for ZKPassport, built using Node.js and TypeScript.
It runs as a containerized service on AWS Fargate and uses the Barretenberg (bb) proving system. The
service is deployed through Amazon ECR and exposed via an Application Load Balancer (ALB).

## Prerequisites

- Node.js 20+
- Docker
- AWS CLI configured
- Access to an AWS account with necessary permissions for ECR, ECS/Fargate, and ALB

## Local Development

To build the Docker image and run the cloud prover locally, run:

```sh
make docker-build-and-run
```

This will give you a local `http://localhost:3000` endpoint to test again.

## Environment Setup

Before deploying to AWS, you need to set the following environment variables:

```sh
export AWS_ACCOUNT_ID=
export AWS_REGION=
export AWS_PROFILE=
```

## Deployment

Login to AWS ECR:

```sh
make aws-login
```

Build and deploy the Docker image to ECR and deploy to AWS Fargate:

```sh
make build-and-deploy
```

## Test

```sh
bun test
```
