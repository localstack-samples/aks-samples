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

# Cosmos DB (NoSQL / SQL API)
COSMOSDB_ACCOUNT_NAME="${PREFIX}-nosql-${SUFFIX}"
AZURECOSMOSDB_DATABASENAME='vacationplanner'
AZURECOSMOSDB_CONTAINERNAME='activities'
AZURECOSMOSDB_PARTITION_KEY='/username'
THROUGHPUT=400

# LocalStack runtime URL. Set to empty when running against real Azure to skip
# the LocalStack root-CA install step in 03-run-docker-container.sh / 05-deploy-app.sh.
LOCALSTACK_URL='http://localhost:4566'

# Application config
LOGIN_NAME='paolo'

# Docker Image
IMAGE_NAME="vacation-planner-nosql"
IMAGE_PULL_POLICY="Always"
IMAGE_TAG="v1"
PORT="8080"

# Kubernetes
NAMESPACE="vacation-planner-nosql"
DEPLOYMENT_NAME="vacation-planner-nosql"
SERVICE_NAME="vacation-planner-nosql"
CONFIGMAP_NAME="vacation-planner-nosql-config"
SECRET_NAME="vacation-planner-nosql-secrets"
