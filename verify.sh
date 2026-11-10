#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_REGION:-eu-west-2}"
ECS_DIR="$ROOT/02-ecs"

for cmd in terraform aws; do
  command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 1; }
done
CLUSTER="$(terraform -chdir="$ECS_DIR" output -raw ecs_cluster_name)"
SERVICE="$(terraform -chdir="$ECS_DIR" output -raw ecs_service_name)"
URL="$(terraform -chdir="$ECS_DIR" output -raw website_url)"

printf 'Website URL: %s\n' "$URL"
printf '\nECS service status:\n'
aws ecs describe-services --region "$REGION" --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].{Status:status,Desired:desiredCount,Running:runningCount,Pending:pendingCount}' --output table
printf '\nHTTP response (expect 200):\n'
if command -v curl >/dev/null; then
  curl -I --max-time 15 "$URL" || true
else
  echo "Open in a browser: $URL"
fi
printf '\nIf running=0, inspect the ECS service Events tab and CloudWatch Logs.\n'
