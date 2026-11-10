#!/usr/bin/env bash
# Provision ECR (if needed), push the website image, and deploy ECS Fargate.
set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ECR_DIR="$PROJECT_ROOT/01-ecr"
ECS_DIR="$PROJECT_ROOT/02-ecs"
AWS_REGION="${AWS_REGION:-eu-west-2}"
SOURCE_DIR="${SOURCE_DIR:-$HOME/morays-project/morays-docker}"
EXISTING_IMAGE_URI="${EXISTING_IMAGE_URI:-}"
ECR_REPOSITORY_URI="${ECR_REPOSITORY_URI:-}"

for cmd in terraform aws; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'ERROR: %s is not installed or is not on PATH in this Ubuntu terminal.\n' "$cmd" >&2
    exit 1
  fi
done

# Earlier in this project the Windows CLI worked even when WSL's native Docker socket did not.
if command -v docker.exe >/dev/null 2>&1; then
  DOCKER="docker.exe"
elif command -v docker >/dev/null 2>&1; then
  DOCKER="docker"
else
  echo 'ERROR: Docker is unavailable. Start Docker Desktop and enable WSL integration.' >&2
  exit 1
fi

printf 'Using region: %s\nDocker command: %s\n' "$AWS_REGION" "$DOCKER"
aws sts get-caller-identity --query '{Account:Account,Arn:Arn}' --output table
"$DOCKER" info --format 'Docker engine: {{.ServerVersion}}' >/dev/null || {
  echo 'ERROR: Docker cannot connect to the engine. Check Docker Desktop.' >&2
  exit 1
}

# AWS resources incur ongoing charges; this must be an informed, deliberate action.
if [[ "${AUTO_APPROVE:-0}" != "1" ]]; then
  echo
  echo 'WARNING: ECS Fargate, the ALB, public IPv4, ECR and CloudWatch can incur AWS charges.'
  read -r -p 'Type DEPLOY to create/update chargeable AWS resources: ' confirmation
  if [[ "$confirmation" != "DEPLOY" ]]; then
    echo 'Cancelled. No deployment started.'
    exit 0
  fi
fi

if [[ -n "$EXISTING_IMAGE_URI" ]]; then
  echo 'Using an existing, already-pushed ECR image; skipping build, push and ECR provisioning.'
  IMAGE_URI="$EXISTING_IMAGE_URI"
else
  if [[ ! -f "$SOURCE_DIR/Dockerfile" ]]; then
    echo "ERROR: No Dockerfile in $SOURCE_DIR" >&2
    echo 'Set SOURCE_DIR to your Morays Docker folder, or use SOURCE_DIR=./sample-site.' >&2
    exit 1
  fi
  if [[ -n "$ECR_REPOSITORY_URI" ]]; then
    echo "Reusing the supplied ECR repository: $ECR_REPOSITORY_URI"
    REPOSITORY_URI="$ECR_REPOSITORY_URI"
  else
    echo '=== 1/3: Create or reuse the Terraform-managed ECR repository ==='
    terraform -chdir="$ECR_DIR" init -input=false
    terraform -chdir="$ECR_DIR" apply -input=false -auto-approve -var="aws_region=$AWS_REGION"
    REPOSITORY_URI="$(terraform -chdir="$ECR_DIR" output -raw repository_url)"
  fi

  REGISTRY_HOST="${REPOSITORY_URI%%/*}"
  IMAGE_TAG="$(date -u +%Y%m%d%H%M%S)-${RANDOM}"
  IMAGE_URI="${REPOSITORY_URI}:${IMAGE_TAG}"

  echo '=== 2/3: Build the Docker image and push it to ECR ==='
  echo "Build folder: $SOURCE_DIR"
  "$DOCKER" build --platform linux/amd64 -t "morays-app:${IMAGE_TAG}" "$SOURCE_DIR"
  "$DOCKER" tag "morays-app:${IMAGE_TAG}" "$IMAGE_URI"
  aws ecr get-login-password --region "$AWS_REGION" | "$DOCKER" login --username AWS --password-stdin "$REGISTRY_HOST"
  "$DOCKER" push "$IMAGE_URI"
fi

printf '\n=== 3/3: Apply ECS, VPC, ALB, IAM, CloudWatch infrastructure ===\n'
terraform -chdir="$ECS_DIR" init -input=false
terraform -chdir="$ECS_DIR" apply -input=false -auto-approve \
  -var="aws_region=$AWS_REGION" \
  -var="image_uri=$IMAGE_URI"

printf '\nDEPLOYMENT COMPLETED.\n'
printf 'Image deployed: %s\n' "$IMAGE_URI"
printf 'Website: '
terraform -chdir="$ECS_DIR" output -raw website_url
printf '\nVerify with: ./verify.sh\n'
