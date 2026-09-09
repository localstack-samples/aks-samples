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

# Cosmos DB (MongoDB API)
COSMOSDB_ACCOUNT_NAME="${PREFIX}-mongodb-${SUFFIX}"
MONGODB_API_VERSION='7.0'
COSMOSDB_DATABASE_NAME='sampledb'
COSMOSDB_COLLECTION_NAME='activities'
INDEXES='[{"key":{"keys":["_id"]}},{"key":{"keys":["username"]}},{"key":{"keys":["activity"]}},{"key":{"keys":["timestamp"]}}]'
SHARD='username'
THROUGHPUT=400

# Application config
LOGIN_NAME='paolo'

# Docker Image
IMAGE_NAME="vacation-planner-mongodb-dotnet"
IMAGE_PULL_POLICY="Always"
IMAGE_TAG="v1"
PORT="8080"

# Kubernetes
NAMESPACE="vacation-planner-mongodb"
DEPLOYMENT_NAME="vacation-planner-mongodb"
SERVICE_NAME="vacation-planner-mongodb"
CONFIGMAP_NAME="vacation-planner-mongodb-config"
SECRET_NAME="vacation-planner-mongodb-secrets"
