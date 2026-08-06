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

# Storage Account
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
CONTAINER_NAME='activities'

# Docker Image
IMAGE_NAME="vacation-planner-blob"
IMAGE_PULL_POLICY="Always"
IMAGE_TAG="v1"
PORT="8080"

# Kubernetes
NAMESPACE="vacation-planner-blob"
DEPLOYMENT_NAME="vacation-planner-blob"
SERVICE_NAME="vacation-planner-blob"
CONFIGMAP_NAME="vacation-planner-blob-config"
SECRET_NAME="vacation-planner-blob-secrets"
