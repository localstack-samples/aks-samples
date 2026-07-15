#!/bin/bash

# Test 4: the "nodeIP" backend-pool variant. When the cluster is created with
# --load-balancer-backend-pool-type nodeIP, the Cloud Controller Manager puts the nodes' private IPs
# directly into the "kubernetes" backend pool (loadBalancerBackendAddresses) instead of referencing
# NIC IP configurations. A public LoadBalancer Service still receives an EXTERNAL-IP.
# https://learn.microsoft.com/en-us/azure/aks/configure-load-balancer-standard
#
# backendPoolType is a create-time cluster property, so this test does NOT create a cluster: it guards
# on the cluster's declared backendPoolType and, when it is not "nodeIP", tells you how to re-create
# the cluster before exiting.

# Variables
source ./00-variables.sh

# Make sure the AKS cluster exists (it is created by 01-user-assigned-managed-identity.sh)
if [[ -z $NODE_RESOURCE_GROUP ]]; then
  echo "Could not resolve the node resource group for the [$AKS_NAME] AKS cluster"
  echo "Create the cluster first with scripts/01-user-assigned-managed-identity.sh"
  exit 1
fi

# This scenario is only meaningful on a nodeIP cluster; the default is nodeIPConfiguration
echo "Checking the backendPoolType of the [$AKS_NAME] AKS cluster..."
BACKEND_POOL_TYPE=$(az aks show \
  --name $AKS_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query "networkProfile.loadBalancerProfile.backendPoolType" \
  --output tsv \
  --only-show-errors)

if [[ $BACKEND_POOL_TYPE != "nodeIP" ]]; then
  echo "This test requires a cluster created with [--load-balancer-backend-pool-type nodeIP]"
  echo "The [$AKS_NAME] cluster reports backendPoolType [$BACKEND_POOL_TYPE]"
  echo "Add [--load-balancer-backend-pool-type nodeIP] to the az aks create command in"
  echo "scripts/01-user-assigned-managed-identity.sh, re-create the cluster, then re-run"
  exit 1
fi

echo "The [$AKS_NAME] cluster uses backendPoolType [$BACKEND_POOL_TYPE]"

# Merge the cluster credentials into kubeconfig and set it as the current context
echo "Merging credentials for the [$AKS_NAME] AKS cluster into kubeconfig..."
az aks get-credentials \
  --name $AKS_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --overwrite-existing \
  --only-show-errors

# Create the namespace if it does not already exist
RESULT=$(kubectl get namespace $NAMESPACE -o jsonpath='{.metadata.name}' 2>/dev/null)
if [[ -n $RESULT ]]; then
  echo "The [$NAMESPACE] namespace already exists"
else
  echo "Creating the [$NAMESPACE] namespace..."
  kubectl create namespace $NAMESPACE
fi

# Deploy the nginx workload the Service selects (idempotent)
echo "Deploying the [$DEPLOYMENT_NAME] nginx deployment to the [$NAMESPACE] namespace..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT_NAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $APP_LABEL
  template:
    metadata:
      labels:
        app: $APP_LABEL
    spec:
      containers:
        - name: nginx
          image: $CONTAINER_IMAGE
          ports:
            - containerPort: $SERVICE_PORT
EOF

# Create the public LoadBalancer Service
echo "Creating the [$NODE_IP_SERVICE_NAME] public LoadBalancer service in the [$NAMESPACE] namespace..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: v1
kind: Service
metadata:
  name: $NODE_IP_SERVICE_NAME
spec:
  type: LoadBalancer
  selector:
    app: $APP_LABEL
  ports:
    - port: $SERVICE_PORT
      targetPort: $SERVICE_PORT
      protocol: TCP
EOF

# Wait for the Cloud Controller Manager to assign the EXTERNAL-IP
echo "Waiting up to [$EXTERNAL_IP_TIMEOUT_SECONDS] seconds for the [$NODE_IP_SERVICE_NAME] service EXTERNAL-IP..."
EXTERNAL_IP=""
DEADLINE=$((SECONDS + EXTERNAL_IP_TIMEOUT_SECONDS))
while [[ $SECONDS -lt $DEADLINE ]]; do
  EXTERNAL_IP=$(kubectl get service $NODE_IP_SERVICE_NAME -n $NAMESPACE \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [[ -n $EXTERNAL_IP ]]; then
    break
  fi
  sleep $SLEEP
done

if [[ -n $EXTERNAL_IP ]]; then
  echo "The [$NODE_IP_SERVICE_NAME] service received EXTERNAL-IP [$EXTERNAL_IP]"
else
  echo "The [$NODE_IP_SERVICE_NAME] service did not receive an EXTERNAL-IP within [$EXTERNAL_IP_TIMEOUT_SECONDS] seconds"
  exit 1
fi

# The CCM creates a dedicated inbound public IP for the service in the node resource group
echo "Looking for a public IP with address [$EXTERNAL_IP] in the [$NODE_RESOURCE_GROUP] node resource group..."
PUBLIC_IP_NAME=$(az network public-ip list \
  --resource-group $NODE_RESOURCE_GROUP \
  --query "[?ipAddress=='$EXTERNAL_IP'].name | [0]" \
  --output tsv \
  --only-show-errors)

if [[ -n $PUBLIC_IP_NAME ]]; then
  echo "Found public IP [$PUBLIC_IP_NAME] with address [$EXTERNAL_IP] in the [$NODE_RESOURCE_GROUP] node resource group"
else
  echo "No public IP with address [$EXTERNAL_IP] found in the [$NODE_RESOURCE_GROUP] node resource group"
  exit 1
fi

# On the nodeIP path the "kubernetes" backend pool holds node private IPs as loadBalancerBackendAddresses
# (not NIC IP configuration references, which is what the default nodeIPConfiguration path uses)
echo "Verifying the [$PUBLIC_LOAD_BALANCER_NAME] backend pool holds node IP addresses..."
BACKEND_ADDRESS_COUNT=$(az network lb address-pool show \
  --resource-group $NODE_RESOURCE_GROUP \
  --lb-name $PUBLIC_LOAD_BALANCER_NAME \
  --name $PUBLIC_LOAD_BALANCER_NAME \
  --query "length(loadBalancerBackendAddresses)" \
  --output tsv \
  --only-show-errors 2>/dev/null)

if [[ -n $BACKEND_ADDRESS_COUNT && $BACKEND_ADDRESS_COUNT -ge 1 ]]; then
  echo "The [$PUBLIC_LOAD_BALANCER_NAME] backend pool holds [$BACKEND_ADDRESS_COUNT] node IP address(es)"
else
  echo "The [$PUBLIC_LOAD_BALANCER_NAME] backend pool holds no node IP addresses (found: [$BACKEND_ADDRESS_COUNT])"
  exit 1
fi

echo "SUCCESS: the [$NODE_IP_SERVICE_NAME] service on the nodeIP cluster received EXTERNAL-IP [$EXTERNAL_IP] with node IPs in the [$PUBLIC_LOAD_BALANCER_NAME] backend pool"
