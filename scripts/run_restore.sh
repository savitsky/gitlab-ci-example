#!/bin/sh
set -eo pipefail

echo "CI_COMMIT_BRANCH: ${CI_COMMIT_BRANCH}"

if [[ "$CI_COMMIT_BRANCH" == "main" ]]; then
  NAMESPACE="${CI_PROJECT_NAME}-prod"
elif [[ "$CI_COMMIT_BRANCH" == "dev" ]]; then
  NAMESPACE="${CI_PROJECT_NAME}-dev"
else
  echo "❌ Unsupported branch: $CI_COMMIT_BRANCH"
  exit 1
fi

echo "Using namespace: $NAMESPACE"

werf run --docker-options="-e MINIO_HOST=$MINIO_HOST -e MINIO_ACCESS_KEY=$MINIO_ACCESS_KEY -e MINIO_SECRET_KEY=$MINIO_SECRET_KEY -e MINIO_BUCKET=$MINIO_BUCKET -e KUBECONFIG_B64=$KUBE_CONFIG -e MONGO_K8S_USER=$MONGO_K8S_USER -e MONGO_K8S_PASS=$MONGO_K8S_PASS" minio -- /usr/local/bin/backup.sh RESTORE "$NAMESPACE"
