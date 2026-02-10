#!/bin/bash
set -e

# ============================================================
# CONFIGURACIÓN
# ============================================================
export AWS_REGION="eu-west-1"
export PROJECT_NAME="pruebaalejandrogolfe"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} CREANDO ROLES IAM${NC}"
echo -e "${BLUE}========================================${NC}"

# ============================================================
# ROL 1: batch-job-role
# Lo usa tu CONTENEDOR DOCKER mientras se ejecuta.
# Le permite: leer/escribir en S3 y arrancar en ECS/Fargate.
# ============================================================
echo -e "\n${BLUE}Creando batch-job-role...${NC}"

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
  --region ${AWS_REGION} 2>/dev/null || echo "Rol ya existe, continuando..."

# S3FullAccess: tu código puede leer la imagen de entrada y escribir el resultado
aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-batch-job-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

# ECSTaskExecutionRolePolicy: permite arrancar el contenedor y escribir logs en CloudWatch
aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-batch-job-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

echo -e "${GREEN}✓ batch-job-role creado y configurado${NC}"

# ============================================================
# ROL 2: batch-service-role
# Lo usa AWS BATCH (el servicio en sí) para gestionar jobs:
# crear contenedores, escalar, comunicarse con ECS internamente.
# ============================================================
echo -e "\n${BLUE}Creando batch-service-role...${NC}"

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
  --region ${AWS_REGION} 2>/dev/null || echo "Rol ya existe, continuando..."

# AWSBatchServiceRole: permisos estándar que Batch necesita para operar
aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-batch-service-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole

echo -e "${GREEN}✓ batch-service-role creado y configurado${NC}"

# ============================================================
# VERIFICACIÓN
# ============================================================
echo -e "\n${BLUE}Verificando roles creados...${NC}"
aws iam get-role --role-name ${PROJECT_NAME}-batch-job-role \
  --query 'Role.RoleName' --output text
aws iam get-role --role-name ${PROJECT_NAME}-batch-service-role \
  --query 'Role.RoleName' --output text

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Roles IAM creados correctamente${NC}"
echo -e "${GREEN}========================================${NC}"

echo "Esperando 10s para que los roles estén activos en AWS..."
sleep 10
echo -e "${GREEN}✓ Listo${NC}"
