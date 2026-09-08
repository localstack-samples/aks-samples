# Variables

# Azure Resources
PREFIX='local'
SUFFIX='test'
LOCATION='italynorth'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
ACR_NAME="${PREFIX,,}acr${SUFFIX,,}"
ACR_SKU='Standard'
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
TENANT_ID=$(az account show --query tenantId --output tsv)
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Azure Database for PostgreSQL flexible server
PG_SERVER_NAME="${PREFIX}-pgflex-${SUFFIX}"
PG_VERSION='16'
PG_SKU_TIER='Burstable'
PG_SKU_NAME='Standard_B1ms'
PG_STORAGE_SIZE_GB=32
PG_BACKUP_RETENTION_DAYS=7
PG_PORT='5432'
FIREWALL_RULE_NAME='AllowAllIPs'
PG_ADMIN_USER='pgadmin'
PG_ADMIN_PASSWORD='P@ssw0rd1234!'
PG_USER_NAME='testuser'
PG_USER_PASSWORD='TestP@ssw0rd123'
PG_DATABASE_NAME='PlannerDB'

# Application config — must match the seed-row `username` in 01-deploy-resources.sh.
# PostgreSQL `=` is case-sensitive (unlike SQL Server), so this stays lowercase.
LOGIN_NAME='paolo'

# Docker Image
IMAGE_NAME="vacation-planner-postgres"
IMAGE_PULL_POLICY="Always"
IMAGE_TAG="v1"
PORT="8080"

# Kubernetes
NAMESPACE="vacation-planner-postgres"
DEPLOYMENT_NAME="vacation-planner-postgres"
SERVICE_NAME="vacation-planner-postgres"
CONFIGMAP_NAME="vacation-planner-postgres-config"
K8S_SECRET_NAME="vacation-planner-postgres-secrets"
