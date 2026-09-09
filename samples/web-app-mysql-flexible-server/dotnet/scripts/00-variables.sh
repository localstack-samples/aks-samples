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

# Azure Database for MySQL flexible server
MYSQL_SERVER_NAME="${PREFIX}-mysqlflex-${SUFFIX}"
MYSQL_VERSION='8.0.21'
MYSQL_SKU_TIER='Burstable'
MYSQL_SKU_NAME='Standard_B1ms'
MYSQL_STORAGE_SIZE_GB=32
MYSQL_BACKUP_RETENTION_DAYS=7
MYSQL_PORT='3306'
FIREWALL_RULE_NAME='AllowAllIPs'
MYSQL_ADMIN_USER='myadmin'
MYSQL_ADMIN_PASSWORD='P@ssw0rd1234!'
MYSQL_USER_NAME='testuser'
MYSQL_USER_PASSWORD='TestP@ssw0rd123'
MYSQL_DATABASE_NAME='plannerdb'
# Azure MySQL Flexible Server (and the LocalStack emulator) default require_secure_transport=ON,
# so the app must connect over TLS. The app enables TLS without certificate verification when
# MYSQL_SSL is truthy, which works against both LocalStack (self-signed cert) and real Azure.
MYSQL_SSL='true'

# Application config — must match the seed-row `username` in 01-deploy-resources.sh.
LOGIN_NAME='paolo'

# Docker Image
IMAGE_NAME="vacation-planner-mysql-dotnet"
IMAGE_PULL_POLICY="Always"
IMAGE_TAG="v1"
PORT="8080"

# Kubernetes
NAMESPACE="vacation-planner-mysql"
DEPLOYMENT_NAME="vacation-planner-mysql"
SERVICE_NAME="vacation-planner-mysql"
CONFIGMAP_NAME="vacation-planner-mysql-config"
K8S_SECRET_NAME="vacation-planner-mysql-secrets"
