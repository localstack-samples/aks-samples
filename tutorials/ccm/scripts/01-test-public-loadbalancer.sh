#!/bin/bash

# Test 1: a public Service of type LoadBalancer receives an EXTERNAL-IP, and the Cloud Controller
# Manager creates a dedicated public IP for it in the node resource group plus a frontend and a rule
# on the "kubernetes" load balancer.
#
# The EXTERNAL-IP is a synthetic, non-routable placeholder (the emulated load balancer has no real
# dataplane): to actually reach the service, use kubectl port-forward.
# https://learn.microsoft.com/en-us/azure/aks/load-balancer-standard

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

# Create the public LoadBalancer Service
echo "Creating the [$PUBLIC_SERVICE_NAME] public LoadBalancer service in the [$NAMESPACE] namespace..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: v1
kind: Service
metadata:
  name: $PUBLIC_SERVICE_NAME
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
echo "Waiting up to [$EXTERNAL_IP_TIMEOUT_SECONDS] seconds for the [$PUBLIC_SERVICE_NAME] service EXTERNAL-IP..."
EXTERNAL_IP=""
DEADLINE=$((SECONDS + EXTERNAL_IP_TIMEOUT_SECONDS))
while [[ $SECONDS -lt $DEADLINE ]]; do
  EXTERNAL_IP=$(kubectl get service $PUBLIC_SERVICE_NAME -n $NAMESPACE \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [[ -n $EXTERNAL_IP ]]; then
    break
  fi
  sleep $SLEEP
done

if [[ -n $EXTERNAL_IP ]]; then
  echo "The [$PUBLIC_SERVICE_NAME] service received EXTERNAL-IP [$EXTERNAL_IP]"
else
  echo "The [$PUBLIC_SERVICE_NAME] service did not receive an EXTERNAL-IP within [$EXTERNAL_IP_TIMEOUT_SECONDS] seconds"
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

# The CCM adds a frontend IP configuration and a load-balancing rule to the "kubernetes" load balancer
echo "Verifying the [$PUBLIC_LOAD_BALANCER_NAME] load balancer frontend and rule in the [$NODE_RESOURCE_GROUP] node resource group..."
FRONTEND_COUNT=$(az network lb show \
  --resource-group $NODE_RESOURCE_GROUP \
  --name $PUBLIC_LOAD_BALANCER_NAME \
  --query "length(frontendIPConfigurations || frontendIpConfigurations)" \
  --output tsv \
  --only-show-errors)
RULE_COUNT=$(az network lb rule list \
  --resource-group $NODE_RESOURCE_GROUP \
  --lb-name $PUBLIC_LOAD_BALANCER_NAME \
  --query "length(@)" \
  --output tsv \
  --only-show-errors)

if [[ -n $FRONTEND_COUNT && $FRONTEND_COUNT -ge 1 && -n $RULE_COUNT && $RULE_COUNT -ge 1 ]]; then
  echo "The [$PUBLIC_LOAD_BALANCER_NAME] load balancer has [$FRONTEND_COUNT] frontend(s) and [$RULE_COUNT] rule(s)"
else
  echo "The [$PUBLIC_LOAD_BALANCER_NAME] load balancer is missing a frontend or a rule (frontends: [$FRONTEND_COUNT], rules: [$RULE_COUNT])"
  exit 1
fi

echo "SUCCESS: the [$PUBLIC_SERVICE_NAME] public LoadBalancer service is backed by node resource group resources"
echo "The EXTERNAL-IP [$EXTERNAL_IP] is a synthetic placeholder; run 'kubectl port-forward -n $NAMESPACE svc/$PUBLIC_SERVICE_NAME 8080:$SERVICE_PORT' to reach nginx"
