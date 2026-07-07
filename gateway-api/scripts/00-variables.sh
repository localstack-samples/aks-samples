# Shared variables for the Gateway API sample tests.
#
# Source this file from every test script with: source ./00-variables.sh
#
# The AKS cluster is created by /home/paolo/azure/aks/scripts/01-user-assigned-managed-identity.sh;
# these values MUST match that script (prefix "local", suffix "test", location "ItalyNorth") so the
# tests target the cluster it creates instead of standing up their own.

# Azure Kubernetes Service (AKS)
PREFIX="local"
SUFFIX="test"
AKS_NAME="${PREFIX}-aks-${SUFFIX}"
AKS_RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOCATION="ItalyNorth"

# The Kubernetes Gateway API resource group suffix carried by every CRD the Managed Gateway API
# installation manages (az aks update --enable-gateway-api installs the standard-channel bundle).
# https://learn.microsoft.com/en-us/azure/aks/managed-gateway-api
GATEWAY_API_GROUP="gateway.networking.k8s.io"

# NGINX Gateway Fabric: the bring-your-own Gateway API implementation. The Managed Gateway API only
# installs the CRDs; an implementation must be deployed separately, exactly like on real AKS. The
# chart is intentionally unpinned (latest), in line with the no-hardcoded-versions rule for this
# feature. The Helm chart registers the "nginx" GatewayClass.
NGF_NAMESPACE="nginx-gateway"
NGF_RELEASE_NAME="ngf"
NGF_OCI_CHART="oci://ghcr.io/nginx/charts/nginx-gateway-fabric"
GATEWAY_CLASS_NAME="nginx"

# Echo-server workload routed through Gateway + HTTPRoute (no cert-manager, no DNS: the hostname is
# local-only and reached via kubectl port-forward with an explicit Host header).
NAMESPACE="gateway-api-test"
DEPLOYMENT_NAME="echoserver"
SERVICE_NAME="echoserver"
GATEWAY_NAME="echoserver"
HTTP_ROUTE_NAME="echoserver"
SAMPLE_HOSTNAME="echo.local"
CONTAINER_IMAGE="ealen/echo-server:latest"
SERVICE_PORT=80

# Local port used by the kubectl port-forward pass-through check against the NGF data-plane Service.
# The LoadBalancer EXTERNAL-IP the emulated CCM assigns is synthetic (not routable from the host).
PORT_FORWARD_LOCAL_PORT=8081

# Readiness polling.
TIMEOUT_SECONDS=300
SLEEP=5
