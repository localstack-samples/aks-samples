#!/bin/bash

# Test 2: a Service annotated as an internal LoadBalancer receives a private EXTERNAL-IP allocated
# from the cluster subnet, materialised on the separate "kubernetes-internal" load balancer, and NO
# public IP is created for it in the node resource group.
# https://learn.microsoft.com/en-us/azure/aks/internal-lb

# Variables
source ./00-variables.sh

# Make sure the AKS cluster exists (it is created by 01-user-assigned-managed-identity.sh)
if [[ -z $NODE_RESOURCE_GROUP ]]; then
  echo "Could not resolve the node resource group for the [$AKS_NAME] AKS cluster"
  echo "Create the cluster first with scripts/01-user-assigned-managed-identity.sh"
  exit 1
fi

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

# Create the internal LoadBalancer Service (the annotation switches the frontend to a private IP)
echo "Creating the [$INTERNAL_SERVICE_NAME] internal LoadBalancer service in the [$NAMESPACE] namespace..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: v1
kind: Service
metadata:
  name: $INTERNAL_SERVICE_NAME
  annotations:
    $INTERNAL_LB_ANNOTATION: "true"
spec:
  type: LoadBalancer
  selector:
    app: $APP_LABEL
  ports:
    - port: $SERVICE_PORT
      targetPort: $SERVICE_PORT
      protocol: TCP
EOF

# Wait for the Cloud Controller Manager to assign the private EXTERNAL-IP
echo "Waiting up to [$EXTERNAL_IP_TIMEOUT_SECONDS] seconds for the [$INTERNAL_SERVICE_NAME] service EXTERNAL-IP..."
EXTERNAL_IP=""
DEADLINE=$((SECONDS + EXTERNAL_IP_TIMEOUT_SECONDS))
while [[ $SECONDS -lt $DEADLINE ]]; do
  EXTERNAL_IP=$(kubectl get service $INTERNAL_SERVICE_NAME -n $NAMESPACE \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [[ -n $EXTERNAL_IP ]]; then
    break
  fi
  sleep $SLEEP
done

if [[ -n $EXTERNAL_IP ]]; then
  echo "The [$INTERNAL_SERVICE_NAME] service received private EXTERNAL-IP [$EXTERNAL_IP]"
else
  echo "The [$INTERNAL_SERVICE_NAME] service did not receive an EXTERNAL-IP within [$EXTERNAL_IP_TIMEOUT_SECONDS] seconds"
  exit 1
fi

# The internal frontend lives on a separate load balancer named "kubernetes-internal"
echo "Verifying the [$INTERNAL_LOAD_BALANCER_NAME] load balancer exists in the [$NODE_RESOURCE_GROUP] node resource group..."
INTERNAL_LB_NAME_FOUND=$(az network lb show \
  --resource-group $NODE_RESOURCE_GROUP \
  --name $INTERNAL_LOAD_BALANCER_NAME \
  --query name \
  --output tsv \
  --only-show-errors 2>/dev/null)

if [[ -n $INTERNAL_LB_NAME_FOUND ]]; then
  echo "Found the [$INTERNAL_LB_NAME_FOUND] internal load balancer; its frontend private IPs are:"
  az network lb show \
    --resource-group $NODE_RESOURCE_GROUP \
    --name $INTERNAL_LOAD_BALANCER_NAME \
    --query "(frontendIPConfigurations || frontendIpConfigurations)[].privateIPAddress" \
    --output tsv \
    --only-show-errors
else
  echo "The [$INTERNAL_LOAD_BALANCER_NAME] internal load balancer was not found in the [$NODE_RESOURCE_GROUP] node resource group"
  exit 1
fi

# An internal LoadBalancer must NOT allocate a public IP: the EXTERNAL-IP is a private subnet address
echo "Confirming no public IP with address [$EXTERNAL_IP] exists in the [$NODE_RESOURCE_GROUP] node resource group..."
PUBLIC_IP_NAME=$(az network public-ip list \
  --resource-group $NODE_RESOURCE_GROUP \
  --query "[?ipAddress=='$EXTERNAL_IP'].name | [0]" \
  --output tsv \
  --only-show-errors)

if [[ -z $PUBLIC_IP_NAME ]]; then
  echo "Confirmed: the [$INTERNAL_SERVICE_NAME] service is backed by a private frontend, not a public IP"
else
  echo "Unexpected: a public IP [$PUBLIC_IP_NAME] with address [$EXTERNAL_IP] exists for an internal service"
  exit 1
fi

echo "SUCCESS: the [$INTERNAL_SERVICE_NAME] internal LoadBalancer service received a private EXTERNAL-IP [$EXTERNAL_IP] on the [$INTERNAL_LOAD_BALANCER_NAME] load balancer"
echo "The EXTERNAL-IP [$EXTERNAL_IP] is a private IP address; run 'kubectl port-forward -n $NAMESPACE svc/$INTERNAL_SERVICE_NAME 8080:$SERVICE_PORT' to reach nginx"