#!/bin/bash

# Test 5: an ingress controller is itself fronted by a Service of type LoadBalancer, so the Cloud
# Controller Manager assigns its controller Service an EXTERNAL-IP and creates a public IP in the node
# resource group, exactly like a plain LoadBalancer Service. This installs the NGINX ingress controller
# via Helm (mirroring 01-user-assigned-managed-identity.sh's ingress install) and asserts that.
#
# It then deploys a backend (Deployment + ClusterIP Service) and an Ingress routing to it, and verifies
# that traffic reaches the backend THROUGH the controller via kubectl port-forward.
#
# The EXTERNAL-IP is a synthetic, non-routable placeholder, but kubectl port-forward against the
# controller Service tunnels straight to the controller pod (bypassing the EXTERNAL-IP entirely), so the
# pass-through works. Without the Ingress created below, the controller has no route and returns its
# default-backend 404 (that is the "does not route" behaviour, not a port-forward failure).
# https://learn.microsoft.com/en-us/azure/aks/app-routing

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

# Install the NGINX ingress controller with Helm if it is not already installed
RESULT=$(helm list --namespace $INGRESS_NAMESPACE 2>/dev/null | grep $INGRESS_RELEASE_NAME | awk '{print $1}')

if [[ -n $RESULT ]]; then
  echo "The [$INGRESS_RELEASE_NAME] ingress controller already exists in the [$INGRESS_NAMESPACE] namespace"
else
  # Add the ingress-nginx Helm repository if it is not already added
  RESULT=$(helm repo list 2>/dev/null | grep $INGRESS_REPO_NAME | awk '{print $1}')

  if [[ -n $RESULT ]]; then
    echo "The [$INGRESS_REPO_NAME] Helm repo already exists"
  else
    echo "Adding the [$INGRESS_REPO_NAME] Helm repo..."
    helm repo add $INGRESS_REPO_NAME $INGRESS_REPO_URL
  fi

  # Update the local Helm chart repository cache
  echo "Updating Helm repos..."
  helm repo update

  # Deploy the NGINX ingress controller (its controller Service is type LoadBalancer). The admission
  # webhook is disabled so the Ingress created below applies cleanly right after install without racing
  # the webhook's certificate/readiness; keep it enabled for production clusters.
  echo "Deploying the [$INGRESS_RELEASE_NAME] NGINX ingress controller to the [$INGRESS_NAMESPACE] namespace..."
  helm install $INGRESS_RELEASE_NAME $INGRESS_REPO_NAME/$INGRESS_CHART_NAME \
    --create-namespace \
    --namespace $INGRESS_NAMESPACE \
    --set controller.replicaCount=1 \
    --set controller.service.type=LoadBalancer \
    --set controller.admissionWebhooks.enabled=false
fi

# Resolve the controller Service name from its labels (do not hardcode the Helm-generated name)
echo "Resolving the ingress controller LoadBalancer service in the [$INGRESS_NAMESPACE] namespace..."
CONTROLLER_SERVICE_NAME=$(kubectl get service \
  --namespace $INGRESS_NAMESPACE \
  --selector app.kubernetes.io/component=controller \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -z $CONTROLLER_SERVICE_NAME ]]; then
  echo "Could not find the ingress controller LoadBalancer service in the [$INGRESS_NAMESPACE] namespace"
  exit 1
fi

echo "Found the [$CONTROLLER_SERVICE_NAME] ingress controller service"

# Wait for the Cloud Controller Manager to assign the controller Service its EXTERNAL-IP
echo "Waiting up to [$EXTERNAL_IP_TIMEOUT_SECONDS] seconds for the [$CONTROLLER_SERVICE_NAME] service EXTERNAL-IP..."
EXTERNAL_IP=""
DEADLINE=$((SECONDS + EXTERNAL_IP_TIMEOUT_SECONDS))
while [[ $SECONDS -lt $DEADLINE ]]; do
  EXTERNAL_IP=$(kubectl get service $CONTROLLER_SERVICE_NAME -n $INGRESS_NAMESPACE \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [[ -n $EXTERNAL_IP ]]; then
    break
  fi
  sleep $SLEEP
done

if [[ -n $EXTERNAL_IP ]]; then
  echo "The [$CONTROLLER_SERVICE_NAME] service received EXTERNAL-IP [$EXTERNAL_IP]"
else
  echo "The [$CONTROLLER_SERVICE_NAME] service did not receive an EXTERNAL-IP within [$EXTERNAL_IP_TIMEOUT_SECONDS] seconds"
  exit 1
fi

# The CCM creates a dedicated public IP for the controller Service in the node resource group
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

echo "The [$CONTROLLER_SERVICE_NAME] ingress controller service received EXTERNAL-IP [$EXTERNAL_IP] backed by a node resource group public IP"

# Create the namespace if it does not already exist
RESULT=$(kubectl get namespace $NAMESPACE -o jsonpath='{.metadata.name}' 2>/dev/null)
if [[ -n $RESULT ]]; then
  echo "The [$NAMESPACE] namespace already exists"
else
  echo "Creating the [$NAMESPACE] namespace..."
  kubectl create namespace $NAMESPACE
fi

# Backend content: a ConfigMap with a recognizable string, mounted as the backend's index.html so the
# pass-through can be asserted (a plain response distinguishes it from the controller default-backend 404)
echo "Creating the [$BACKEND_CONFIG_MAP_NAME] config map in the [$NAMESPACE] namespace..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: $BACKEND_CONFIG_MAP_NAME
data:
  index.html: "$BACKEND_RESPONSE_TEXT"
EOF

# Backend Deployment: nginx serving the ConfigMap content
echo "Deploying the [$BACKEND_DEPLOYMENT_NAME] backend deployment to the [$NAMESPACE] namespace..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $BACKEND_DEPLOYMENT_NAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $BACKEND_APP_LABEL
  template:
    metadata:
      labels:
        app: $BACKEND_APP_LABEL
    spec:
      containers:
        - name: nginx
          image: $CONTAINER_IMAGE
          ports:
            - containerPort: $SERVICE_PORT
          volumeMounts:
            - name: content
              mountPath: /usr/share/nginx/html
      volumes:
        - name: content
          configMap:
            name: $BACKEND_CONFIG_MAP_NAME
EOF

# Backend Service of type ClusterIP (reachable only inside the cluster; the Ingress fronts it)
echo "Creating the [$BACKEND_SERVICE_NAME] ClusterIP service in the [$NAMESPACE] namespace..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: v1
kind: Service
metadata:
  name: $BACKEND_SERVICE_NAME
spec:
  type: ClusterIP
  selector:
    app: $BACKEND_APP_LABEL
  ports:
    - port: $SERVICE_PORT
      targetPort: $SERVICE_PORT
      protocol: TCP
EOF

# Ingress routing every request (path "/", no host) to the backend Service via the "nginx" class
echo "Creating the [$INGRESS_NAME] ingress routing to the [$BACKEND_SERVICE_NAME] service..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $INGRESS_NAME
spec:
  ingressClassName: $INGRESS_CLASS_NAME
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: $BACKEND_SERVICE_NAME
                port:
                  number: $SERVICE_PORT
EOF

# Wait for the controller pod and the backend to be ready before exercising the pass-through
echo "Waiting for the ingress controller pod to be ready..."
kubectl wait \
  --namespace $INGRESS_NAMESPACE \
  --for=condition=ready pod \
  --selector app.kubernetes.io/component=controller \
  --timeout=180s

echo "Waiting for the [$BACKEND_DEPLOYMENT_NAME] backend deployment to be available..."
kubectl rollout status deployment/$BACKEND_DEPLOYMENT_NAME -n $NAMESPACE --timeout=120s

# Pass-through check: forward a local port to the controller Service, then curl through it. port-forward
# tunnels straight to the controller pod, so it works despite the non-routable EXTERNAL-IP; the Ingress
# is what makes the controller route "/" to the backend.
echo "Verifying the pass-through via 'kubectl port-forward' against the [$CONTROLLER_SERVICE_NAME] service..."
kubectl port-forward \
  --namespace $INGRESS_NAMESPACE \
  svc/$CONTROLLER_SERVICE_NAME \
  $PORT_FORWARD_LOCAL_PORT:80 >/dev/null 2>&1 &
PORT_FORWARD_PID=$!

PASS_THROUGH_BODY=""
DEADLINE=$((SECONDS + 60))
while [[ $SECONDS -lt $DEADLINE ]]; do
  PASS_THROUGH_BODY=$(curl --silent --max-time 5 "http://localhost:$PORT_FORWARD_LOCAL_PORT/" 2>/dev/null)
  if echo "$PASS_THROUGH_BODY" | grep -qF "$BACKEND_RESPONSE_TEXT"; then
    break
  fi
  sleep $SLEEP
done

# Stop the background port-forward
kill $PORT_FORWARD_PID 2>/dev/null
wait $PORT_FORWARD_PID 2>/dev/null

if echo "$PASS_THROUGH_BODY" | grep -qF "$BACKEND_RESPONSE_TEXT"; then
  echo "Pass-through OK: reached the [$BACKEND_SERVICE_NAME] backend through the [$CONTROLLER_SERVICE_NAME] controller (response: [$BACKEND_RESPONSE_TEXT])"
else
  echo "Pass-through check did not return the backend response within the timeout (the controller pod may still be warming up)"
  echo "Retry manually with the commands below"
fi

echo "SUCCESS: the [$CONTROLLER_SERVICE_NAME] ingress controller has EXTERNAL-IP [$EXTERNAL_IP] and the [$INGRESS_NAME] ingress routes to the [$BACKEND_SERVICE_NAME] backend"
echo "Reach the backend through the controller (this bypasses the synthetic, non-routable EXTERNAL-IP):"
echo "  kubectl port-forward -n $INGRESS_NAMESPACE svc/$CONTROLLER_SERVICE_NAME $PORT_FORWARD_LOCAL_PORT:80"
echo "  curl http://localhost:$PORT_FORWARD_LOCAL_PORT/"
