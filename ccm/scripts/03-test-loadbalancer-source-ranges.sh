#!/bin/bash

# Test 3: a public Service with spec.loadBalancerSourceRanges causes the Cloud Controller Manager to
# reconcile an inbound Allow rule on the node resource group NSG, restricted to the given client CIDR.
# https://learn.microsoft.com/en-us/azure/aks/configure-load-balancer-standard

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

# Create a public LoadBalancer Service restricted to a single client CIDR via loadBalancerSourceRanges
echo "Creating the [$RESTRICTED_SERVICE_NAME] restricted LoadBalancer service (source range [$ALLOWED_SOURCE_RANGE])..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: v1
kind: Service
metadata:
  name: $RESTRICTED_SERVICE_NAME
spec:
  type: LoadBalancer
  selector:
    app: $APP_LABEL
  loadBalancerSourceRanges:
    - $ALLOWED_SOURCE_RANGE
  ports:
    - port: $SERVICE_PORT
      targetPort: $SERVICE_PORT
      protocol: TCP
EOF

# Wait for the Cloud Controller Manager to assign the EXTERNAL-IP (the NSG rule is written during the
# same reconcile that assigns the address)
echo "Waiting up to [$EXTERNAL_IP_TIMEOUT_SECONDS] seconds for the [$RESTRICTED_SERVICE_NAME] service EXTERNAL-IP..."
EXTERNAL_IP=""
DEADLINE=$((SECONDS + EXTERNAL_IP_TIMEOUT_SECONDS))
while [[ $SECONDS -lt $DEADLINE ]]; do
  EXTERNAL_IP=$(kubectl get service $RESTRICTED_SERVICE_NAME -n $NAMESPACE \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [[ -n $EXTERNAL_IP ]]; then
    break
  fi
  sleep $SLEEP
done

if [[ -n $EXTERNAL_IP ]]; then
  echo "The [$RESTRICTED_SERVICE_NAME] service received EXTERNAL-IP [$EXTERNAL_IP]"
else
  echo "The [$RESTRICTED_SERVICE_NAME] service did not receive an EXTERNAL-IP within [$EXTERNAL_IP_TIMEOUT_SECONDS] seconds"
  exit 1
fi

# Resolve the node resource group NSG the CCM reconciles service rules into
NSG_NAME=$(az network nsg list \
  --resource-group $NODE_RESOURCE_GROUP \
  --query "[0].name" \
  --output tsv \
  --only-show-errors)

if [[ -z $NSG_NAME ]]; then
  echo "No network security group found in the [$NODE_RESOURCE_GROUP] node resource group"
  exit 1
fi

# Show the current inbound rules for visibility, then assert the restricted Allow rule is present
echo "Inbound rules on the [$NSG_NAME] network security group:"
az network nsg rule list \
  --resource-group $NODE_RESOURCE_GROUP \
  --nsg-name $NSG_NAME \
  --query "[?direction=='Inbound'].{name:name, access:access, port:destinationPortRange, source:sourceAddressPrefix, sources:sourceAddressPrefixes}" \
  --output table \
  --only-show-errors

# The CCM writes the allowed CIDR into sourceAddressPrefix (single) or sourceAddressPrefixes (array).
# Collect both fields from inbound Allow rules and match the range as a fixed string (grep -F), which
# sidesteps JMESPath null-array handling and any casing quirks in the emulated response.
echo "Looking for an inbound Allow rule for port [$SERVICE_PORT] restricted to [$ALLOWED_SOURCE_RANGE]..."
ALLOW_RULE_SOURCES=$(az network nsg rule list \
  --resource-group $NODE_RESOURCE_GROUP \
  --nsg-name $NSG_NAME \
  --query "[?access=='Allow' && direction=='Inbound'].[sourceAddressPrefix, sourceAddressPrefixes]" \
  --output tsv \
  --only-show-errors)

if echo "$ALLOW_RULE_SOURCES" | grep -qF "$ALLOWED_SOURCE_RANGE"; then
  echo "Found an inbound Allow rule restricted to [$ALLOWED_SOURCE_RANGE]"
else
  echo "No inbound Allow rule restricted to [$ALLOWED_SOURCE_RANGE] found on the [$NSG_NAME] network security group"
  exit 1
fi

echo "SUCCESS: the [$RESTRICTED_SERVICE_NAME] service reconciled an NSG allow-rule scoped to [$ALLOWED_SOURCE_RANGE]"
