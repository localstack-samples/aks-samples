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

# Azure SQL
SQL_SERVER_NAME="${PREFIX}-sqlserver-${SUFFIX}"
FIREWALL_RULE_NAME='AllowAllIPs'
ADMIN_USER='sqladmin'
ADMIN_PASSWORD='P@ssw0rd1234!'
DATABASE_USER_NAME='testuser'
DATABASE_USER_PASSWORD='TestP@ssw0rd123'
SQL_DATABASE_NAME='PlannerDB'

# Application config
LOGIN_NAME='Paolo'

# Docker Image
IMAGE_NAME="vacation-planner-sql"
IMAGE_PULL_POLICY="Always"
IMAGE_TAG="v1"
PORT="8080"

# Kubernetes
NAMESPACE="vacation-planner-sql"
DEPLOYMENT_NAME="vacation-planner-sql"
SERVICE_NAME="vacation-planner-sql"
CONFIGMAP_NAME="vacation-planner-sql-config"
K8S_SECRET_NAME="vacation-planner-sql-secrets"
