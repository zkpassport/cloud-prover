# Set dotenv-load to automatically load environment variables from .env file
set dotenv-load

# List available recipes
default:
    @just --list

# Check required environment variables
check-env:
    #!/usr/bin/env sh
    if [ -z "${AWS_ACCOUNT_ID}" ]; then
        echo "❌ ERROR: AWS_ACCOUNT_ID is not set!"
        exit 1
    fi
    if [ -z "${AWS_REGION}" ]; then
        echo "❌ ERROR: AWS_REGION is not set!"
        exit 1
    fi
    if [ -z "${AWS_PROFILE}" ]; then
        echo "❌ ERROR: AWS_PROFILE is not set!"
        exit 1
    fi

# Build Docker image
docker-build:
    docker buildx build --platform linux/arm64 --tag zkpassport/cloud-prover .

# Build Docker image without cache
docker-build-no-cache:
    docker buildx build --platform linux/arm64 --no-cache --tag zkpassport/cloud-prover .

# Run Docker container
docker-run:
    docker run --platform linux/arm64 -p 3000:3000 --rm --name cloud-prover -it zkpassport/cloud-prover

# Build and run Docker container
docker-build-and-run: docker-build docker-run

# Tag and push Docker image to ECR
docker-tag-and-push: check-env
    #!/usr/bin/env sh
    ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/zkpassport/cloud-prover"
    docker tag zkpassport/cloud-prover:latest ${ECR_REPO}:latest
    docker push ${ECR_REPO}:latest
    echo "Image pushed to: ${ECR_REPO}:latest"

# Login to AWS ECR
aws-login: check-env
    #!/usr/bin/env sh
    aws ecr get-login-password --region ${AWS_REGION} --profile ${AWS_PROFILE} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Build and deploy to ECS
build-and-deploy: docker-build docker-tag-and-push
    aws ecs update-service --cluster zkpassport-cloud-prover --service zkpassport-cloud-prover-service --force-new-deployment
    @echo "🚀 Successfully built, pushed, and deployed!"
