#!/bin/bash
set -e

export AWS_REGION="eu-west-1"
export PROJECT_NAME="image-processor-alejandrogolfe-2"
export BUCKET_NAME="${PROJECT_NAME}-bucket-$(date +%s)"
export ECR_REPO="image-processor-alejandrogolfe-2"
export BATCH_JOB_NAME="${PROJECT_NAME}-job"
export COMPUTE_ENV_NAME="${PROJECT_NAME}-compute-env"
export JOB_QUEUE_NAME="${PROJECT_NAME}-queue"
export LAMBDA_NAME="${PROJECT_NAME}-trigger"


# Cargar configuración
if [ ! -f .deployment-config ]; then
  echo "❌ No se encontró .deployment-config"
  exit 1
fi

# Limpiar posibles saltos de línea de Windows en el config al cargar
source <(sed 's/\r$//' .deployment-config)

echo "🗑️  ELIMINANDO RECURSOS..."
echo "Proyecto: ${PROJECT_NAME}"

# 1. Trigger S3
aws s3api put-bucket-notification-configuration --bucket "${BUCKET_NAME}" --notification-configuration '{}' --region "${AWS_REGION}" 2>/dev/null || true

# 2. Lambda
aws lambda delete-function --function-name "${LAMBDA_NAME}" --region "${AWS_REGION}" 2>/dev/null || true

# 3. S3 Bucket
aws s3 rm "s3://${BUCKET_NAME}" --recursive 2>/dev/null || true
aws s3 rb "s3://${BUCKET_NAME}" 2>/dev/null || true

# 4 y 5. Batch Queue
aws batch update-job-queue --job-queue "${JOB_QUEUE_NAME}" --state DISABLED --region "${AWS_REGION}" 2>/dev/null || true
sleep 5
aws batch delete-job-queue --job-queue "${JOB_QUEUE_NAME}" --region "${AWS_REGION}" 2>/dev/null || true

# 6 y 7. Compute Environment
aws batch update-compute-environment --compute-environment "${COMPUTE_ENV_NAME}" --state DISABLED --region "${AWS_REGION}" 2>/dev/null || true
sleep 10
aws batch delete-compute-environment --compute-environment "${COMPUTE_ENV_NAME}" --region "${AWS_REGION}" 2>/dev/null || true

# 8. Job Definitions
REVISIONS=$(aws batch describe-job-definitions --job-definition-name "${BATCH_JOB_NAME}" --query 'jobDefinitions[*].revision' --output text --region "${AWS_REGION}" 2>/dev/null) || REVISIONS=""
for rev in $REVISIONS; do
  aws batch deregister-job-definition --job-definition "${BATCH_JOB_NAME}:${rev}" --region "${AWS_REGION}" 2>/dev/null || true
done

# 9. ECR
aws ecr delete-repository --repository-name "${ECR_REPO}" --force --region "${AWS_REGION}" 2>/dev/null || true

# 10. IAM Roles
for role in "${PROJECT_NAME}-batch-job-role" "${PROJECT_NAME}-batch-service-role" "${PROJECT_NAME}-lambda-role"; do
  POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null) || POLICIES=""
  for policy in $POLICIES; do
    aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>/dev/null || true
  done
  aws iam delete-role --role-name "$role" 2>/dev/null || true
done

# 11. Limpieza final
rm -f batch-job-role-trust.json batch-service-role-trust.json lambda-role-trust.json job-definition.json s3-notification.json lambda_function.py lambda.zip .deployment-config
echo "✅ RECURSOS ELIMINADOS"
