#!/usr/bin/env bash
# Destroy ECS resources first; optionally destroy the dedicated training ECR repository.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_REGION:-eu-west-2}"
ECS_DIR="$ROOT/02-ecs"
ECR_DIR="$ROOT/01-ecr"
command -v terraform >/dev/null || { echo 'Terraform not found' >&2; exit 1; }

printf 'DESTROY AWS INFRASTRUCTURE in %s (ALB, Fargate, VPC, logs and more).\n' "$REGION"
printf 'ECR images will only be deleted if DELETE_ECR=1 and the ECR repository was created by this project.\n'
read -r -p 'Type DESTROY to continue: ' confirmation
[[ "$confirmation" == "DESTROY" ]] || { echo 'Cancelled.'; exit 0; }

if [[ -f "$ECS_DIR/terraform.tfstate" ]]; then
  terraform -chdir="$ECS_DIR" init -input=false
  # Terraform destroy needs the required input variable but the state identifies the actual resources.
  terraform -chdir="$ECS_DIR" destroy -input=false -auto-approve \
    -var="aws_region=$REGION" -var="image_uri=not-used-during-destroy"
else
  echo 'No local ECS state found. Not attempting a blind destroy.'
fi

if [[ "${DELETE_ECR:-0}" == "1" ]]; then
  if [[ -f "$ECR_DIR/terraform.tfstate" ]]; then
    echo 'WARNING: destroying the training ECR repository also permanently deletes its images.'
    read -r -p 'Type DELETE_IMAGES to confirm ECR deletion: ' second_confirmation
    if [[ "$second_confirmation" == "DELETE_IMAGES" ]]; then
      terraform -chdir="$ECR_DIR" init -input=false
      terraform -chdir="$ECR_DIR" destroy -input=false -auto-approve -var="aws_region=$REGION"
    else
      echo 'ECR kept.'
    fi
  else
    echo 'No local ECR state found; will not delete any repository.'
  fi
else
  echo 'ECR repository retained. To also delete your dedicated project ECR repo: DELETE_ECR=1 ./destroy.sh'
fi
