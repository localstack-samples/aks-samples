#!/bin/bash

# Step 2: create (or reuse) the user-assigned managed identity that the three KEDA tutorials share,
# federate it to the keda-operator service account, and bind the operator to it by annotating that
# service account and restarting the operator.
#
# The keda-operator service account exists once, in kube-system, so a single shared identity is what
# lets the three KEDA tutorials coexist on one cluster: the first tutorial you run creates the
# identity and the binding, and the others find both already in place.
# https://learn.microsoft.com/en-us/azure/aks/keda-workload-identity
#
# This tutorial federates the same identity a second time, to the queue-app service account the
# producer and the consumer run as, so the applications can exchange their own projected token for a
# Microsoft Entra token too. That second credential is what makes this the only one of the three
# tutorials with no connection string and no secret.
# https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview

# Variables
source ./00-variables.sh

# Get or create the shared user-assigned managed identity
echo "Checking if the [$MANAGED_IDENTITY_NAME] managed identity exists in the [$AKS_RESOURCE_GROUP_NAME] resource group..."
az identity show \
  --name $MANAGED_IDENTITY_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --only-show-errors &>/dev/null

if [[ $? -ne 0 ]]; then
  echo "No [$MANAGED_IDENTITY_NAME] managed identity exists in the [$AKS_RESOURCE_GROUP_NAME] resource group"
  echo "Creating the [$MANAGED_IDENTITY_NAME] managed identity..."

  az identity create \
    --name $MANAGED_IDENTITY_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --location $LOCATION \
    --only-show-errors 1>/dev/null

  if [[ $? -eq 0 ]]; then
    echo "The [$MANAGED_IDENTITY_NAME] managed identity was successfully created"
  else
    echo "Failed to create the [$MANAGED_IDENTITY_NAME] managed identity"
    exit 1
  fi
else
  echo "The [$MANAGED_IDENTITY_NAME] managed identity already exists"
fi

# The client id identifies the identity when a workload authenticates; the principal (object) id is
# what role assignments are granted to. They are different values and are not interchangeable.
MANAGED_IDENTITY_CLIENT_ID=$(az identity show \
  --name $MANAGED_IDENTITY_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query clientId \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $MANAGED_IDENTITY_CLIENT_ID ]]; then
  echo "Failed to retrieve the client id of the [$MANAGED_IDENTITY_NAME] managed identity"
  exit 1
fi
echo "The client id of the [$MANAGED_IDENTITY_NAME] managed identity is [$MANAGED_IDENTITY_CLIENT_ID]"

# Retrieve the cluster's OIDC issuer URL, the trust anchor of the federated credentials
AKS_OIDC_ISSUER_URL=$(az aks show \
  --name $AKS_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query oidcIssuerProfile.issuerUrl \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $AKS_OIDC_ISSUER_URL ]]; then
  echo "Failed to retrieve the OIDC issuer URL of the [$AKS_NAME] AKS cluster"
  echo "Make sure the cluster was created with the OIDC issuer enabled (az aks update --enable-oidc-issuer)"
  exit 1
fi
echo "The OIDC issuer URL of the [$AKS_NAME] AKS cluster is [$AKS_OIDC_ISSUER_URL]"

# Get or create the federated credential for the KEDA operator's service account
echo "Checking if the [$FEDERATED_IDENTITY_NAME_KEDA] federated credential exists on the [$MANAGED_IDENTITY_NAME] managed identity..."
az identity federated-credential show \
  --name $FEDERATED_IDENTITY_NAME_KEDA \
  --identity-name $MANAGED_IDENTITY_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --only-show-errors &>/dev/null

if [[ $? -ne 0 ]]; then
  echo "No [$FEDERATED_IDENTITY_NAME_KEDA] federated credential exists on the [$MANAGED_IDENTITY_NAME] managed identity"
  echo "Creating the [$FEDERATED_IDENTITY_NAME_KEDA] federated credential..."

  az identity federated-credential create \
    --name $FEDERATED_IDENTITY_NAME_KEDA \
    --identity-name $MANAGED_IDENTITY_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --issuer $AKS_OIDC_ISSUER_URL \
    --subject system:serviceaccount:${KEDA_NAMESPACE}:${KEDA_OPERATOR_SERVICE_ACCOUNT} \
    --audience $FEDERATED_IDENTITY_AUDIENCE \
    --only-show-errors 1>/dev/null

  if [[ $? -eq 0 ]]; then
    echo "The [$FEDERATED_IDENTITY_NAME_KEDA] federated credential was successfully created"
  else
    echo "Failed to create the [$FEDERATED_IDENTITY_NAME_KEDA] federated credential"
    exit 1
  fi
else
  echo "The [$FEDERATED_IDENTITY_NAME_KEDA] federated credential already exists"
fi

# Get or create the federated credential for the application service account, the one the producer and
# the consumer pods run as. It is created here, before the namespace and the service account exist,
# because a federated credential is a property of the managed identity: it only names the subject, and
# the subject is resolved when a pod presents its token.
echo "Checking if the [$FEDERATED_IDENTITY_NAME_APP] federated credential exists on the [$MANAGED_IDENTITY_NAME] managed identity..."
az identity federated-credential show \
  --name $FEDERATED_IDENTITY_NAME_APP \
  --identity-name $MANAGED_IDENTITY_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --only-show-errors &>/dev/null

if [[ $? -ne 0 ]]; then
  echo "No [$FEDERATED_IDENTITY_NAME_APP] federated credential exists on the [$MANAGED_IDENTITY_NAME] managed identity"
  echo "Creating the [$FEDERATED_IDENTITY_NAME_APP] federated credential..."

  az identity federated-credential create \
    --name $FEDERATED_IDENTITY_NAME_APP \
    --identity-name $MANAGED_IDENTITY_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --issuer $AKS_OIDC_ISSUER_URL \
    --subject system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT_NAME} \
    --audience $FEDERATED_IDENTITY_AUDIENCE \
    --only-show-errors 1>/dev/null

  if [[ $? -eq 0 ]]; then
    echo "The [$FEDERATED_IDENTITY_NAME_APP] federated credential was successfully created"
  else
    echo "Failed to create the [$FEDERATED_IDENTITY_NAME_APP] federated credential"
    exit 1
  fi
else
  echo "The [$FEDERATED_IDENTITY_NAME_APP] federated credential already exists"
fi

# The KEDA add-on owns the operator: AKS installs the keda-operator service account and deployment in
# kube-system when --enable-keda is set, so this tutorial never creates them, it only binds them to the
# managed identity. Confirm they are there first, otherwise the annotation and the restart below fail
# with a bare NotFound that says nothing about the cause.
kubectl get serviceaccount $KEDA_OPERATOR_SERVICE_ACCOUNT --namespace $KEDA_NAMESPACE &>/dev/null
SERVICE_ACCOUNT_EXISTS=$?
kubectl get deployment $KEDA_OPERATOR_DEPLOYMENT --namespace $KEDA_NAMESPACE &>/dev/null
DEPLOYMENT_EXISTS=$?
if [[ $SERVICE_ACCOUNT_EXISTS -ne 0 || $DEPLOYMENT_EXISTS -ne 0 ]]; then
  echo "The KEDA add-on has not installed the [$KEDA_OPERATOR_SERVICE_ACCOUNT] service account and the [$KEDA_OPERATOR_DEPLOYMENT] deployment in the [$KEDA_NAMESPACE] namespace yet"
  echo "Run 01-enable-keda.sh first: it enables the add-on and waits for it to come up"
  kubectl get serviceaccount,deployment --namespace $KEDA_NAMESPACE 2>/dev/null | grep keda
  exit 1
fi

# Bind the operator to the identity. The annotation tells the workload-identity webhook which identity
# to project a token for, and the webhook applies it when a pod is admitted, so pods that were already
# running do not have it: the operator has to be restarted for the binding to take effect. This is the
# step the Microsoft tutorial calls out as well.
# https://learn.microsoft.com/en-us/azure/aks/keda-workload-identity
# The restart is skipped when the annotation is already the one we want.
CURRENT_CLIENT_ID=$(kubectl get serviceaccount $KEDA_OPERATOR_SERVICE_ACCOUNT \
  --namespace $KEDA_NAMESPACE \
  --output jsonpath='{.metadata.annotations.azure\.workload\.identity/client-id}' 2>/dev/null)

if [[ "$CURRENT_CLIENT_ID" == "$MANAGED_IDENTITY_CLIENT_ID" ]]; then
  echo "The [$KEDA_OPERATOR_SERVICE_ACCOUNT] service account is already bound to the [$MANAGED_IDENTITY_NAME] managed identity"
else
  echo "Annotating the [$KEDA_OPERATOR_SERVICE_ACCOUNT] service account with the client id of the [$MANAGED_IDENTITY_NAME] managed identity..."
  kubectl annotate serviceaccount $KEDA_OPERATOR_SERVICE_ACCOUNT \
    --namespace $KEDA_NAMESPACE \
    azure.workload.identity/client-id=$MANAGED_IDENTITY_CLIENT_ID \
    --overwrite
  if [[ $? -ne 0 ]]; then
    echo "Failed to annotate the [$KEDA_OPERATOR_SERVICE_ACCOUNT] service account"
    exit 1
  fi

  echo "Restarting the [$KEDA_OPERATOR_DEPLOYMENT] deployment so the workload-identity variables are injected..."
  kubectl rollout restart deployment/$KEDA_OPERATOR_DEPLOYMENT --namespace $KEDA_NAMESPACE
  kubectl rollout status deployment/$KEDA_OPERATOR_DEPLOYMENT \
    --namespace $KEDA_NAMESPACE \
    --timeout=${TIMEOUT_SECONDS}s
  if [[ $? -ne 0 ]]; then
    echo "The [$KEDA_OPERATOR_DEPLOYMENT] deployment did not become ready after the restart"
    exit 1
  fi
fi

# Report the add-on's final state: the operator is now bound to the identity, so this is the point
# where the component list is meaningful. The deployment names differ between the AKS managed add-on
# (keda-operator-metrics-apiserver, keda-admission-webhooks) and the upstream bundle the LocalStack
# emulator installs (keda-metrics-apiserver, keda-admission), so they are listed, not asserted.
KEDA_VERSION=$(kubectl get crd/$KEDA_SCALED_OBJECT_CRD \
  --output jsonpath='{.metadata.labels.app\.kubernetes\.io/version}' 2>/dev/null)
echo "KEDA [$KEDA_VERSION] is running in the [$KEDA_NAMESPACE] namespace, bound to the [$MANAGED_IDENTITY_NAME] managed identity:"
kubectl get deployments --namespace $KEDA_NAMESPACE --no-headers 2>/dev/null | grep keda
