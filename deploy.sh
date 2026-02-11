#!/bin/bash
set -e  # Parar si hay error

# ============================================================
# CONFIGURACION - CAMBIA ESTOS VALORES
# ============================================================
export AWS_REGION="eu-west-1"
export PROJECT_NAME="image-processor-alejandrogolfe-2"
export BUCKET_NAME="${PROJECT_NAME}-bucket"
export ECR_REPO="image-processor-alejandrogolfe-2"
export BATCH_JOB_NAME="${PROJECT_NAME}-job"
export COMPUTE_ENV_NAME="${PROJECT_NAME}-compute-env"
export JOB_QUEUE_NAME="${PROJECT_NAME}-queue"
export LAMBDA_NAME="${PROJECT_NAME}-trigger"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} AWS BATCH DEPLOYMENT${NC}"
echo -e "${BLUE}========================================${NC}"

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}Account ID: ${AWS_ACCOUNT_ID}${NC}"

# ============================================================
# PASO 1: CREAR BUCKET S3
# ============================================================
echo -e "\n${BLUE} PASO 1: Creando bucket S3...${NC}"
aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION} 2>/dev/null || echo "Bucket ya existe"
echo -e "${GREEN}Bucket: ${BUCKET_NAME}${NC}"

aws s3api put-object --bucket ${BUCKET_NAME} --key input/ --region ${AWS_REGION} 2>/dev/null || true
aws s3api put-object --bucket ${BUCKET_NAME} --key output/ --region ${AWS_REGION} 2>/dev/null || true
echo -e "${GREEN}Carpetas input/ y output/ creadas${NC}"

# ============================================================
# PASO 2: CREAR REPOSITORIO ECR
# ============================================================
echo -e "\n${BLUE} PASO 2: Creando repositorio ECR...${NC}"
aws ecr create-repository \
  --repository-name ${ECR_REPO} \
  --region ${AWS_REGION} || echo "Repo ya existe"
echo -e "${GREEN}ECR Repo: ${ECR_REPO}${NC}"

# ============================================================
# PASO 3: BUILD Y PUSH DE DOCKER
# ============================================================
echo -e "\n${BLUE} PASO 3: Building imagen Docker...${NC}"

aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

docker build -t ${ECR_REPO} .
echo -e "${GREEN}Imagen built${NC}"

docker tag ${ECR_REPO}:latest \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:latest

docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:latest
echo -e "${GREEN}Imagen pushed a ECR${NC}"

# ============================================================
# PASO 4: CREAR ROLES IAM
# ============================================================
echo -e "\n${BLUE} PASO 4: Creando roles IAM...${NC}"

cat > batch-job-role-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name ${PROJECT_NAME}-batch-job-role \
  --assume-role-policy-document file://batch-job-role-trust.json \
  --region ${AWS_REGION} 2>/dev/null || echo "Rol ya existe"

aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-batch-job-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-batch-job-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

cat > batch-service-role-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "batch.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name ${PROJECT_NAME}-batch-service-role \
  --assume-role-policy-document file://batch-service-role-trust.json \
  --region ${AWS_REGION} 2>/dev/null || echo "Rol ya existe"

aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-batch-service-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole

echo -e "${GREEN}Roles IAM creados${NC}"
echo "Esperando 10s para que los roles esten activos..."
sleep 10

# ============================================================
# PASO 5: CREAR COMPUTE ENVIRONMENT
# ============================================================
echo -e "\n${BLUE} PASO 5: Creando Compute Environment...${NC}"

EXISTING_CE=$(aws batch describe-compute-environments \
  --compute-environments ${COMPUTE_ENV_NAME} \
  --query 'computeEnvironments[0].computeEnvironmentName' \
  --output text --region ${AWS_REGION} 2>/dev/null || echo "")

if [ "$EXISTING_CE" = "${COMPUTE_ENV_NAME}" ]; then
  echo -e "${GREEN}Compute Environment ya existe, reutilizando${NC}"
else
  aws batch create-compute-environment \
    --compute-environment-name ${COMPUTE_ENV_NAME} \
    --type MANAGED \
    --state ENABLED \
    --compute-resources type=FARGATE,maxvCpus=4,subnets=$(aws ec2 describe-subnets --filters "Name=default-for-az,Values=true" --query 'Subnets[0].SubnetId' --output text --region ${AWS_REGION}),securityGroupIds=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text --region ${AWS_REGION}) \
    --service-role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-batch-service-role \
    --region ${AWS_REGION}
  echo -e "${GREEN}Compute Environment creado${NC}"
fi

echo "Esperando a que Compute Environment este listo..."
while true; do
  STATUS=$(aws batch describe-compute-environments \
    --compute-environments ${COMPUTE_ENV_NAME} \
    --query 'computeEnvironments[0].status' \
    --output text \
    --region ${AWS_REGION})
  if [ "$STATUS" = "VALID" ]; then
    echo -e "${GREEN}Compute Environment listo${NC}"
    break
  fi
  echo "  Status: $STATUS (esperando...)"
  sleep 5
done

# ============================================================
# PASO 6: CREAR JOB QUEUE
# ============================================================
echo -e "\n${BLUE} PASO 6: Creando Job Queue...${NC}"

EXISTING_JQ=$(aws batch describe-job-queues \
  --job-queues ${JOB_QUEUE_NAME} \
  --query 'jobQueues[0].jobQueueName' \
  --output text --region ${AWS_REGION} 2>/dev/null || echo "")

if [ "$EXISTING_JQ" = "${JOB_QUEUE_NAME}" ]; then
  echo -e "${GREEN}Job Queue ya existe, reutilizando${NC}"
else
  aws batch create-job-queue \
    --job-queue-name ${JOB_QUEUE_NAME} \
    --state ENABLED \
    --priority 1 \
    --compute-environment-order order=1,computeEnvironment=${COMPUTE_ENV_NAME} \
    --region ${AWS_REGION}
  echo -e "${GREEN}Job Queue creado${NC}"
fi

echo "Esperando a que Job Queue este listo..."
while true; do
  STATUS=$(aws batch describe-job-queues \
    --job-queues ${JOB_QUEUE_NAME} \
    --query 'jobQueues[0].status' \
    --output text \
    --region ${AWS_REGION})
  if [ "$STATUS" = "VALID" ]; then
    echo -e "${GREEN}Job Queue listo${NC}"
    break
  fi
  echo "  Status: $STATUS (esperando...)"
  sleep 5
done

# ============================================================
# PASO 7: CREAR JOB DEFINITION
# ============================================================
echo -e "\n${BLUE} PASO 7: Creando Job Definition...${NC}"

cat > job-definition.json << EOF
{
  "jobDefinitionName": "${BATCH_JOB_NAME}",
  "type": "container",
  "platformCapabilities": ["FARGATE"],
  "containerProperties": {
    "image": "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:latest",
    "resourceRequirements": [
      {"type": "VCPU", "value": "0.25"},
      {"type": "MEMORY", "value": "512"}
    ],
    "jobRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-batch-job-role",
    "executionRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-batch-job-role",
    "fargatePlatformConfiguration": {
      "platformVersion": "LATEST"
    },
    "networkConfiguration": {
      "assignPublicIp": "ENABLED"
    }
  }
}
EOF

aws batch register-job-definition \
  --cli-input-json file://job-definition.json \
  --region ${AWS_REGION}

echo -e "${GREEN}Job Definition creado${NC}"

# ============================================================
# PASO 8: CREAR LAMBDA TRIGGER
# ============================================================
echo -e "\n${BLUE} PASO 8: Creando Lambda trigger...${NC}"

cat > lambda-role-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name ${PROJECT_NAME}-lambda-role \
  --assume-role-policy-document file://lambda-role-trust.json \
  --region ${AWS_REGION} 2>/dev/null || echo "Rol ya existe"

aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/AWSBatchFullAccess

echo "Esperando 10s para que el rol Lambda este activo..."
sleep 10

cat > lambda_function.py << EOF
import json
import boto3
import os

batch = boto3.client('batch')

def lambda_handler(event, context):
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']

    print(f"Nueva imagen: s3://{bucket}/{key}")

    response = batch.submit_job(
        jobName=f"process-{key.replace('/', '-').replace('.', '-')}",
        jobQueue='${JOB_QUEUE_NAME}',
        jobDefinition='${BATCH_JOB_NAME}',
        containerOverrides={
            'environment': [
                {'name': 'BUCKET', 'value': bucket},
                {'name': 'INPUT_KEY', 'value': key}
            ]
        }
    )

    print(f"Batch job submitted: {response['jobId']}")

    return {'statusCode': 200, 'jobId': response['jobId']}
EOF

zip lambda.zip lambda_function.py

EXISTING_LAMBDA=$(aws lambda get-function \
  --function-name ${LAMBDA_NAME} \
  --region ${AWS_REGION} \
  --query 'Configuration.FunctionName' \
  --output text 2>/dev/null || echo "")

if [ "$EXISTING_LAMBDA" = "${LAMBDA_NAME}" ]; then
  echo "Lambda ya existe, actualizando codigo..."
  aws lambda update-function-code \
    --function-name ${LAMBDA_NAME} \
    --zip-file fileb://lambda.zip \
    --region ${AWS_REGION}
  echo -e "${GREEN}Lambda actualizada${NC}"
else
  aws lambda create-function \
    --function-name ${LAMBDA_NAME} \
    --runtime python3.12 \
    --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://lambda.zip \
    --timeout 60 \
    --region ${AWS_REGION}
  echo -e "${GREEN}Lambda creada${NC}"
fi

# ============================================================
# PASO 9: CONFIGURAR S3 TRIGGER
# ============================================================
echo -e "\n${BLUE} PASO 9: Configurando trigger S3 -> Lambda...${NC}"

aws lambda add-permission \
  --function-name ${LAMBDA_NAME} \
  --statement-id s3-trigger \
  --action lambda:InvokeFunction \
  --principal s3.amazonaws.com \
  --source-arn arn:aws:s3:::${BUCKET_NAME} \
  --region ${AWS_REGION} 2>/dev/null || echo "Permiso S3 ya existe"

cat > s3-notification.json << EOF
{
  "LambdaFunctionConfigurations": [{
    "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_NAME}",
    "Events": ["s3:ObjectCreated:*"],
    "Filter": {
      "Key": {
        "FilterRules": [{"Name": "prefix", "Value": "input/"}]
      }
    }
  }]
}
EOF

aws s3api put-bucket-notification-configuration \
  --bucket ${BUCKET_NAME} \
  --notification-configuration file://s3-notification.json

echo -e "${GREEN}Trigger S3 configurado${NC}"

# ============================================================
# RESUMEN
# ============================================================
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN} DESPLIEGUE COMPLETADO${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "  Bucket S3:       ${BLUE}${BUCKET_NAME}${NC}"
echo -e "  ECR Repo:        ${BLUE}${ECR_REPO}${NC}"
echo -e "  Compute Env:     ${BLUE}${COMPUTE_ENV_NAME}${NC}"
echo -e "  Job Queue:       ${BLUE}${JOB_QUEUE_NAME}${NC}"
echo -e "  Job Definition:  ${BLUE}${BATCH_JOB_NAME}${NC}"
echo -e "  Lambda:          ${BLUE}${LAMBDA_NAME}${NC}"
echo ""
echo -e "${BLUE}PROBAR:${NC}"
echo "  aws s3 cp test.jpg s3://${BUCKET_NAME}/input/test.jpg"
echo ""
echo -e "${BLUE}VER LOGS:${NC}"
echo "  aws logs tail /aws/lambda/${LAMBDA_NAME} --follow"
echo ""

cat > .deployment-config << EOF
AWS_REGION=${AWS_REGION}
PROJECT_NAME=${PROJECT_NAME}
BUCKET_NAME=${BUCKET_NAME}
ECR_REPO=${ECR_REPO}
BATCH_JOB_NAME=${BATCH_JOB_NAME}
COMPUTE_ENV_NAME=${COMPUTE_ENV_NAME}
JOB_QUEUE_NAME=${JOB_QUEUE_NAME}
LAMBDA_NAME=${LAMBDA_NAME}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
EOF

echo -e "${GREEN}Configuracion guardada en .deployment-config${NC}"
