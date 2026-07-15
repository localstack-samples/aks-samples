# Variables
source ../00-variables.sh

# Azure Managed Identity
MANAGED_IDENTITY_NAME="${PREFIX}-identity-${SUFFIX}"
FEDERATED_IDENTITY_NAME="federated-identity"

# Kubernetes
NAMESPACE="mi-secret-store-test"
SECRET_PROVIDER_CLASS_NAME="demo-secret-provider-class"
POD_NAME="demo-pod"