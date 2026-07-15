#!/bin/bash

# Step 3: deploy the echo-server sample routed through the Gateway API: a Deployment, a ClusterIP
# Service, a Gateway (class "nginx", HTTP listener on a local-only hostname), and an HTTPRoute.
# No cert-manager and no DNS: the hostname is reached via kubectl port-forward with an explicit
# Host header (step 4). Every apply is idempotent.

# Variables
source ./00-variables.sh

# Make sure the nginx GatewayClass exists (step 2)
if ! kubectl get gatewayclass $GATEWAY_CLASS_NAME &>/dev/null; then
  echo "The [$GATEWAY_CLASS_NAME] GatewayClass does not exist"
  echo "Run ./02-install-nginx-gateway-fabric.sh first"
  exit 1
fi

# Create the namespace if it does not already exist
RESULT=$(kubectl get namespace $NAMESPACE -o jsonpath='{.metadata.name}' 2>/dev/null)
if [[ -n $RESULT ]]; then
  echo "The [$NAMESPACE] namespace already exists"
else
  echo "Creating the [$NAMESPACE] namespace..."
  kubectl create namespace $NAMESPACE
fi

# Deploy the echo-server workload and its ClusterIP Service
echo "Deploying the [$DEPLOYMENT_NAME] deployment and [$SERVICE_NAME] service to the [$NAMESPACE] namespace..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT_NAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $DEPLOYMENT_NAME
  template:
    metadata:
      labels:
        app: $DEPLOYMENT_NAME
    spec:
      nodeSelector:
        "kubernetes.io/os": linux
      containers:
        - image: $CONTAINER_IMAGE
          imagePullPolicy: IfNotPresent
          name: $DEPLOYMENT_NAME
          resources:
            requests:
              memory: "64Mi"
              cpu: "125m"
            limits:
              memory: "128Mi"
              cpu: "250m"
          ports:
            - containerPort: $SERVICE_PORT
          env:
            - name: PORT
              value: "$SERVICE_PORT"
---
apiVersion: v1
kind: Service
metadata:
  name: $SERVICE_NAME
spec:
  ports:
    - port: $SERVICE_PORT
      targetPort: $SERVICE_PORT
      protocol: TCP
  type: ClusterIP
  selector:
    app: $DEPLOYMENT_NAME
EOF

# Create the Gateway and the HTTPRoute binding the hostname to the backend Service
echo "Deploying the [$GATEWAY_NAME] gateway and [$HTTP_ROUTE_NAME] HTTP route for host [$SAMPLE_HOSTNAME]..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: $GATEWAY_NAME
spec:
  gatewayClassName: $GATEWAY_CLASS_NAME
  listeners:
    - hostname: $SAMPLE_HOSTNAME
      name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: All
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: $HTTP_ROUTE_NAME
spec:
  hostnames:
    - $SAMPLE_HOSTNAME
  parentRefs:
    - name: $GATEWAY_NAME
      sectionName: http
  rules:
    - backendRefs:
        - name: $SERVICE_NAME
          port: $SERVICE_PORT
      matches:
        - path:
            type: PathPrefix
            value: /
EOF

# Wait for the Gateway to be Programmed (NGF provisions its per-Gateway nginx data plane) and the
# backend Deployment to be Available
echo "Waiting for the [$GATEWAY_NAME] gateway to be Programmed..."
kubectl wait -n $NAMESPACE --for=condition=Programmed gateway/$GATEWAY_NAME --timeout=${TIMEOUT_SECONDS}s
if [[ $? -ne 0 ]]; then
  echo "The [$GATEWAY_NAME] gateway was not Programmed within $TIMEOUT_SECONDS seconds"
  exit 1
fi

echo "Waiting for the [$DEPLOYMENT_NAME] deployment to be Available..."
kubectl wait -n $NAMESPACE --for=condition=Available deployment/$DEPLOYMENT_NAME --timeout=${TIMEOUT_SECONDS}s
if [[ $? -ne 0 ]]; then
  echo "The [$DEPLOYMENT_NAME] deployment did not become Available within $TIMEOUT_SECONDS seconds"
  exit 1
fi

echo "The [$GATEWAY_NAME] gateway and [$HTTP_ROUTE_NAME] HTTP route are deployed and ready"
echo "The [$DEPLOYMENT_NAME] deployment and [$SERVICE_NAME] service are deployed and ready"
echo "The [$SAMPLE_HOSTNAME] hostname is routed to the [$SERVICE_NAME] service"
echo "Here are the resources deployed in the [$NAMESPACE] namespace:"
kubectl get gateway,httproute,deployment,service -n $NAMESPACE
