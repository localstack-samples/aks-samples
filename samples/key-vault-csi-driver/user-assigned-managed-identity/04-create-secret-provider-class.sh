#/bin/bash

# For more information, see:
# https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver
# https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-identity-access

# Variables
source ./00-variables.sh

# Get the clientId of the Azure Key Vault Secrets Provider identity
KV_IDENTITY_CLIENT_ID=$(az aks show \
	--resource-group $AKS_RESOURCE_GROUP_NAME \
	--name $AKS_NAME \
	--query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId \
	--output tsv \
	--only-show-errors)

if [[ -n $KV_IDENTITY_CLIENT_ID ]]; then
	echo "Successfully retrieved the clientId for the Azure Key Vault Secrets Provider identity in the [$AKS_NAME] AKS cluster"
else
	echo "Failed to retrieve the clientId for the Azure Key Vault Secrets Provider identity in the [$AKS_NAME] AKS cluster"
	exit
fi

echo "KV_IDENTITY_CLIENT_ID: $KV_IDENTITY_CLIENT_ID"
echo "KEY_VAULT_NAME: $KEY_VAULT_NAME"
echo "TENANT_ID: $TENANT_ID"

# Check if the namespace exists in the cluster
RESULT=$(kubectl get namespace -o 'jsonpath={.items[?(@.metadata.name=="'$NAMESPACE'")].metadata.name'})

if [[ -n $RESULT ]]; then
  echo "[$NAMESPACE] namespace already exists in the cluster"
else
  echo "[$NAMESPACE] namespace does not exist in the cluster"
  echo "Creating [$NAMESPACE] namespace in the cluster..."
  kubectl create namespace $NAMESPACE
fi

# Create the SecretProviderClass for the secret store CSI driver with Azure Key Vault provider
echo "Creating the SecretProviderClass for the secret store CSI driver with Azure Key Vault provider..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name:  $SECRET_PROVIDER_CLASS_NAME
spec:
  provider: azure
  parameters:
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "$KV_IDENTITY_CLIENT_ID"
    keyvaultName: "$KEY_VAULT_NAME"
    tenantId: "$TENANT_ID"
    objects:  |
      array:
        - |
          objectName: username
          objectAlias: username
          objectType: secret        
          objectVersion: ""
        - |
          objectName: password
          objectAlias: password
          objectType: secret
          objectVersion: ""
EOF
