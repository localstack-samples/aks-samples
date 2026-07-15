# Azure Kubernetes Service (AKS)
PREFIX="local"
SUFFIX="test"
AKS_NAME="${PREFIX}-aks-${SUFFIX}"
AKS_RESOURCE_GROUP_NAME="${PREFIX}-rg"

# Azure Key Vault
KEY_VAULT_NAME="${PREFIX}-kv-${SUFFIX}"
KEY_VAULT_RESOURCE_GROUP_NAME="${PREFIX}-rg"
KEY_VAULT_SKU="Standard"
LOCATION="WestEurope" # Choose a location

# Secrets and Values 
SECRETS=("username" "password")
VALUES=("admin" "trustno1!")

# Azure Subscription and Tenant
TENANT_ID=$(az account show --query tenantId --output tsv --only-show-errors)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv --only-show-errors)
SUBSCRIPTION_ID=$(az account show --query id --output tsv --only-show-errors)
ENVIRONMENT_NAME=$(az account show --query environmentName --output tsv --only-show-errors)

# Others
RETRY_COUNT=5
SLEEP=3