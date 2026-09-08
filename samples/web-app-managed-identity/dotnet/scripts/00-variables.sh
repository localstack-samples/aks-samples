# Variables

# Azure Resources
PREFIX='local'
SUFFIX='test'
LOCATION='italynorth'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
AKS_CLUSTER_NAME="${PREFIX}-aks-${SUFFIX}"
ACR_NAME="${PREFIX,,}acr${SUFFIX,,}"
ACR_SKU='Standard'
MANAGED_IDENTITY_NAME="${PREFIX}-app-identity-${SUFFIX}"
FEDERATED_IDENTITY_NAME="${PREFIX}-federated-identity-${SUFFIX}"
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
TENANT_ID=$(az account show --query tenantId --output tsv)
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

# DNS
DNS_ZONE_RESOURCE_GROUP_NAME="dns-rg"
DNS_ZONE_NAME="babosbird.com"
SUBDOMAIN="planner.local"

# Storage Account
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
CONTAINER_NAME='activities'

# Docker Image
IMAGE_NAME="vacation-planner-identity-dotnet"
IMAGE_PULL_POLICY="Always"
IMAGE_TAG="v1"
PORT="8080"

# Kubernetes
NAME="vacation-planner-identity"
NAMESPACE="vacation-planner-identity"
DEPLOYMENT_NAME="vacation-planner-identity"
SERVICE_NAME="vacation-planner-identity"
CONFIGMAP_NAME="vacation-planner-identity-config"
SECRET_NAME="vacation-planner-identity-secrets"
SERVICE_ACCOUNT_NAME="vacation-planner-identity-sa"
DEPLOY_GATEWAY="false"
