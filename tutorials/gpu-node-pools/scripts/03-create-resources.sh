#!/bin/bash

# Step 3: create (or reuse) the Service Bus namespace and the queue the training requests arrive on, and the managed
# identity the KEDA operator and the training job sign in with:
#  - the identity gets the Azure Service Bus Data Owner role on the namespace, on its principal (object) id;
#  - it is federated with the keda-operator service account, so the operator can read the queue's message count, and
#    with the training job's service account, so the job can receive a message;
#  - the keda-operator service account is annotated with the identity's client id, and the operator restarted so the
#    workload identity variables are injected. This step is skipped when the annotation is already in place, for
#    example because one of the KEDA tutorials, which share the identity, ran first.
# https://learn.microsoft.com/en-us/azure/aks/keda-workload-identity

# Variables
source ./00-variables.sh

# Get or create the Service Bus namespace
echo "Checking if the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace exists in the [$AKS_RESOURCE_GROUP_NAME] resource group..."
if az servicebus namespace show \
  --name "$SERVICE_BUS_NAMESPACE_NAME" \
  --resource-group "$AKS_RESOURCE_GROUP_NAME" \
  --only-show-errors &>/dev/null; then
  echo "The [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace already exists"
else
  echo "Creating the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace..."
  if ! az servicebus namespace create \
    --name "$SERVICE_BUS_NAMESPACE_NAME" \
    --resource-group "$AKS_RESOURCE_GROUP_NAME" \
    --location "$LOCATION" \
    --sku "$SERVICE_BUS_SKU" \
    --only-show-errors 1>/dev/null; then
    echo "Failed to create the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace"
    exit 1
  fi
  echo "The [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace was successfully created"
fi

# Get or create the queue
echo "Checking if the [$SERVICE_BUS_QUEUE_NAME] queue exists in the [$SERVICE_BUS_NAMESPACE_NAME] namespace..."
if az servicebus queue show \
  --name "$SERVICE_BUS_QUEUE_NAME" \
  --namespace-name "$SERVICE_BUS_NAMESPACE_NAME" \
  --resource-group "$AKS_RESOURCE_GROUP_NAME" \
  --only-show-errors &>/dev/null; then
  echo "The [$SERVICE_BUS_QUEUE_NAME] queue already exists"
else
  echo "Creating the [$SERVICE_BUS_QUEUE_NAME] queue..."
  if ! az servicebus queue create \
    --name "$SERVICE_BUS_QUEUE_NAME" \
    --namespace-name "$SERVICE_BUS_NAMESPACE_NAME" \
    --resource-group "$AKS_RESOURCE_GROUP_NAME" \
    --only-show-errors 1>/dev/null; then
    echo "Failed to create the [$SERVICE_BUS_QUEUE_NAME] queue"
    exit 1
  fi
  echo "The [$SERVICE_BUS_QUEUE_NAME] queue was successfully created"
fi

# Get or create the managed identity
echo "Checking if the [$MANAGED_IDENTITY_NAME] managed identity exists in the [$AKS_RESOURCE_GROUP_NAME] resource group..."
if az identity show \
  --name "$MANAGED_IDENTITY_NAME" \
  --resource-group "$AKS_RESOURCE_GROUP_NAME" \
  --only-show-errors &>/dev/null; then
  echo "The [$MANAGED_IDENTITY_NAME] managed identity already exists"
else
  echo "Creating the [$MANAGED_IDENTITY_NAME] managed identity..."
  if ! az identity create \
    --name "$MANAGED_IDENTITY_NAME" \
    --resource-group "$AKS_RESOURCE_GROUP_NAME" \
    --location "$LOCATION" \
    --only-show-errors 1>/dev/null; then
    echo "Failed to create the [$MANAGED_IDENTITY_NAME] managed identity"
    exit 1
  fi
  echo "The [$MANAGED_IDENTITY_NAME] managed identity was successfully created"
fi

# The client id identifies the identity when a workload signs in; the principal (object) id is what role assignments
# are granted to. They are different values and are not interchangeable.
MANAGED_IDENTITY_CLIENT_ID=$(az identity show \
  --name "$MANAGED_IDENTITY_NAME" \
  --resource-group "$AKS_RESOURCE_GROUP_NAME" \
  --query clientId \
  --output tsv \
  --only-show-errors 2>/dev/null | tr -d '\r')
MANAGED_IDENTITY_PRINCIPAL_ID=$(az identity show \
  --name "$MANAGED_IDENTITY_NAME" \
  --resource-group "$AKS_RESOURCE_GROUP_NAME" \
  --query principalId \
  --output tsv \
  --only-show-errors 2>/dev/null | tr -d '\r')
if [[ -z $MANAGED_IDENTITY_CLIENT_ID || -z $MANAGED_IDENTITY_PRINCIPAL_ID ]]; then
  echo "Failed to retrieve the client id and the principal id of the [$MANAGED_IDENTITY_NAME] managed identity"
  exit 1
fi

# Grant the role on the namespace unless the identity already has it
SERVICE_BUS_NAMESPACE_ID=$(az servicebus namespace show \
  --name "$SERVICE_BUS_NAMESPACE_NAME" \
  --resource-group "$AKS_RESOURCE_GROUP_NAME" \
  --query id \
  --output tsv \
  --only-show-errors 2>/dev/null | tr -d '\r')
if [[ -z $SERVICE_BUS_NAMESPACE_ID ]]; then
  echo "Failed to retrieve the resource id of the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace"
  exit 1
fi
ROLE_ASSIGNMENT=$(az role assignment list \
  --assignee "$MANAGED_IDENTITY_PRINCIPAL_ID" \
  --scope "$SERVICE_BUS_NAMESPACE_ID" \
  --query "[?roleDefinitionName=='$ROLE'].roleDefinitionName" \
  --output tsv \
  --only-show-errors 2>/dev/null | tr -d '\r')
if [[ -n $ROLE_ASSIGNMENT ]]; then
  echo "The [$MANAGED_IDENTITY_NAME] managed identity already has the [$ROLE] role on the [$SERVICE_BUS_NAMESPACE_NAME] namespace"
else
  echo "Granting the [$ROLE] role on the [$SERVICE_BUS_NAMESPACE_NAME] namespace to the [$MANAGED_IDENTITY_NAME] managed identity..."
  if ! az role assignment create \
    --assignee-object-id "$MANAGED_IDENTITY_PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "$ROLE" \
    --scope "$SERVICE_BUS_NAMESPACE_ID" \
    --only-show-errors 1>/dev/null; then
    echo "Failed to grant the [$ROLE] role to the [$MANAGED_IDENTITY_NAME] managed identity"
    exit 1
  fi
  echo "The [$ROLE] role was successfully granted"
fi

# Federate the identity with the keda-operator service account and with the training job's service account
AKS_OIDC_ISSUER_URL=$(az aks show \
  --name "$AKS_NAME" \
  --resource-group "$AKS_RESOURCE_GROUP_NAME" \
  --query oidcIssuerProfile.issuerUrl \
  --output tsv \
  --only-show-errors 2>/dev/null | tr -d '\r')
if [[ -z $AKS_OIDC_ISSUER_URL ]]; then
  echo "Failed to retrieve the OIDC issuer URL of the [$AKS_NAME] AKS cluster"
  exit 1
fi
for FEDERATION in \
  "$FEDERATED_IDENTITY_NAME_KEDA system:serviceaccount:$KEDA_NAMESPACE:$KEDA_OPERATOR_SERVICE_ACCOUNT" \
  "$FEDERATED_IDENTITY_NAME_JOB system:serviceaccount:$NAMESPACE:$SERVICE_ACCOUNT_NAME"; do
  FEDERATED_IDENTITY_NAME=${FEDERATION%% *}
  SUBJECT=${FEDERATION#* }
  if az identity federated-credential show \
    --name "$FEDERATED_IDENTITY_NAME" \
    --identity-name "$MANAGED_IDENTITY_NAME" \
    --resource-group "$AKS_RESOURCE_GROUP_NAME" \
    --only-show-errors &>/dev/null; then
    echo "The [$FEDERATED_IDENTITY_NAME] federated identity credential already exists"
    continue
  fi
  echo "Federating the [$MANAGED_IDENTITY_NAME] managed identity with [$SUBJECT]..."
  if ! az identity federated-credential create \
    --name "$FEDERATED_IDENTITY_NAME" \
    --identity-name "$MANAGED_IDENTITY_NAME" \
    --resource-group "$AKS_RESOURCE_GROUP_NAME" \
    --issuer "$AKS_OIDC_ISSUER_URL" \
    --subject "$SUBJECT" \
    --audiences "$FEDERATED_IDENTITY_AUDIENCE" \
    --only-show-errors 1>/dev/null; then
    echo "Failed to create the [$FEDERATED_IDENTITY_NAME] federated identity credential"
    exit 1
  fi
  echo "The [$FEDERATED_IDENTITY_NAME] federated identity credential was successfully created"
done

# Bind the KEDA operator to the identity, unless its service account already names it
CURRENT_CLIENT_ID=$(kubectl get serviceaccount "$KEDA_OPERATOR_SERVICE_ACCOUNT" \
  --namespace "$KEDA_NAMESPACE" \
  --output jsonpath='{.metadata.annotations.azure\.workload\.identity/client-id}' 2>/dev/null)
if [[ $CURRENT_CLIENT_ID == "$MANAGED_IDENTITY_CLIENT_ID" ]]; then
  echo "The [$KEDA_OPERATOR_SERVICE_ACCOUNT] service account is already bound to the [$MANAGED_IDENTITY_NAME] managed identity"
else
  echo "Binding the [$KEDA_OPERATOR_SERVICE_ACCOUNT] service account to the [$MANAGED_IDENTITY_NAME] managed identity..."
  if ! kubectl annotate serviceaccount "$KEDA_OPERATOR_SERVICE_ACCOUNT" \
    --namespace "$KEDA_NAMESPACE" \
    "azure.workload.identity/client-id=$MANAGED_IDENTITY_CLIENT_ID" \
    --overwrite; then
    echo "Failed to annotate the [$KEDA_OPERATOR_SERVICE_ACCOUNT] service account"
    exit 1
  fi
  # The workload identity variables are injected only when the operator's pods start
  echo "Restarting the [$KEDA_OPERATOR_DEPLOYMENT] deployment..."
  if ! kubectl rollout restart deployment "$KEDA_OPERATOR_DEPLOYMENT" --namespace "$KEDA_NAMESPACE"; then
    echo "Failed to restart the [$KEDA_OPERATOR_DEPLOYMENT] deployment"
    exit 1
  fi
  if ! kubectl rollout status deployment "$KEDA_OPERATOR_DEPLOYMENT" --namespace "$KEDA_NAMESPACE" --timeout=300s; then
    echo "The [$KEDA_OPERATOR_DEPLOYMENT] deployment didn't restart in time"
    exit 1
  fi
fi
