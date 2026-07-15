# Shared variables for the Cloud Controller Manager (CCM) sample tests.
#
# Source this file from every test script with: source ./00-variables.sh
#
# The AKS cluster is created by scripts/01-user-assigned-managed-identity.sh;
# these values MUST match that script (prefix "local", suffix "test", location "ItalyNorth") so the
# tests target the cluster it creates instead of standing up their own.

# Azure Kubernetes Service (AKS)
PREFIX="local"
SUFFIX="test"
AKS_NAME="${PREFIX}-aks-${SUFFIX}"
AKS_RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOCATION="ItalyNorth"

# Node resource group (the MC_* resource group the AKS RP manages). The CCM writes the per-service
# public IP, the LoadBalancer frontend and rule, and the NSG allow-rules here, so the tests assert
# against it. Derived from the cluster so it is never hardcoded (empty when the cluster does not exist).
NODE_RESOURCE_GROUP=$(az aks show \
  --name $AKS_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query nodeResourceGroup \
  --output tsv \
  --only-show-errors 2>/dev/null)

# The primary Standard load balancer the AKS RP pre-creates in the node resource group. The CCM adds
# each public LoadBalancer Service's frontend, rule, and backend pool to it. Real AKS and the upstream
# cloud-provider-azure Helm chart default the name (and the inbound backend pool) to "kubernetes".
PUBLIC_LOAD_BALANCER_NAME="kubernetes"
# Internal LoadBalancer Services land on a separate load balancer named "kubernetes-internal".
INTERNAL_LOAD_BALANCER_NAME="kubernetes-internal"

# Kubernetes namespace and the nginx workload the LoadBalancer Services select (tests 1 to 4).
NAMESPACE="ccm-test"
DEPLOYMENT_NAME="nginx"
APP_LABEL="nginx"
CONTAINER_IMAGE="nginx:1.27-alpine"
SERVICE_PORT=80

# One Service name per scenario, so the tests can coexist on the same cluster.
PUBLIC_SERVICE_NAME="nginx-public-lb"
INTERNAL_SERVICE_NAME="nginx-internal-lb"
RESTRICTED_SERVICE_NAME="nginx-restricted-lb"
NODE_IP_SERVICE_NAME="nginx-nodeip-lb"

# Annotation that turns a Service into an internal LoadBalancer (test 2). The frontend IP is then
# allocated privately from the cluster subnet instead of a public IP.
# https://learn.microsoft.com/en-us/azure/aks/internal-lb
INTERNAL_LB_ANNOTATION="service.beta.kubernetes.io/azure-load-balancer-internal"

# Client CIDR allowed to reach the restricted public Service (test 3). The CCM reconciles this into an
# inbound Allow rule on the node resource group NSG. 203.0.113.0/24 is the RFC 5737 TEST-NET-3 range.
ALLOWED_SOURCE_RANGE="203.0.113.0/24"

# NGINX ingress controller (test 5). Its own front Service is type LoadBalancer, so the CCM assigns it
# an EXTERNAL-IP the same way. Mirrors 01-user-assigned-managed-identity.sh's ingress install.
INGRESS_NAMESPACE="ingress-basic"
INGRESS_RELEASE_NAME="nginx-ingress"
INGRESS_REPO_NAME="ingress-nginx"
INGRESS_REPO_URL="https://kubernetes.github.io/ingress-nginx"
INGRESS_CHART_NAME="ingress-nginx"

# Backend workload behind the ingress (test 5 extension). A Deployment plus a ClusterIP Service, with
# an Ingress object routing to it, so a request that passes through the controller reaches a real
# backend. The backend serves a recognizable string (via a ConfigMap) so the pass-through is assertable.
BACKEND_DEPLOYMENT_NAME="ingress-backend"
BACKEND_SERVICE_NAME="ingress-backend"
BACKEND_APP_LABEL="ingress-backend"
BACKEND_CONFIG_MAP_NAME="ingress-backend-content"
BACKEND_RESPONSE_TEXT="Hello from the ingress backend"

# The Ingress routes every request (path "/", no host) to the backend Service, so no Host header is
# needed to reach it through the controller. It targets the "nginx" IngressClass the chart installs.
INGRESS_NAME="ingress-backend"
INGRESS_CLASS_NAME="nginx"

# Local port used by the kubectl port-forward pass-through check against the controller Service.
PORT_FORWARD_LOCAL_PORT=8080

# EXTERNAL-IP polling. The CCM writes the address only after the whole reconcile (frontend public IP,
# LB rule, backend-pool membership) completes, which can take a few minutes on a loaded emulator.
EXTERNAL_IP_TIMEOUT_SECONDS=300
SLEEP=5
