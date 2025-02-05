.PHONY: docker-build docker-run docker-tag-and-push

check-env:
	@if [ -z "$(AWS_ACCOUNT_ID)" ]; then \
		echo "❌ ERROR: AWS_ACCOUNT_ID is not set!"; \
		exit 1; \
	fi
	@if [ -z "$(AWS_REGION)" ]; then \
		echo "❌ ERROR: AWS_REGION is not set!"; \
		exit 1; \
	fi
	@if [ -z "$(AWS_PROFILE)" ]; then \
		echo "❌ ERROR: AWS_PROFILE is not set!"; \
		exit 1; \
	fi

docker-build:
	docker buildx build --platform linux/arm64 --tag zkpassport/cloud-prover .

docker-build-no-cache:
	docker buildx build --platform linux/arm64 --no-cache --tag zkpassport/cloud-prover .

docker-run:
	docker run --platform linux/arm64 -p 3000:3000 --rm --name cloud-prover -it zkpassport/cloud-prover

docker-build-and-run: docker-build docker-run

docker-tag-and-push: check-env
	docker tag zkpassport/cloud-prover:latest $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/zkpassport/cloud-prover:latest
	docker push $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/zkpassport/cloud-prover:latest
	@echo Image pushed to: $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/zkpassport/cloud-prover:latest

aws-login: check-env
	aws ecr get-login-password --region $(AWS_REGION) --profile $(AWS_PROFILE) | docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com

build-and-deploy: docker-build docker-tag-and-push
	aws ecs update-service --cluster zkpassport-cloud-prover --service zkpassport-cloud-prover-service --force-new-deployment
	@echo "🚀 Successfully built, pushed, and deployed!"
