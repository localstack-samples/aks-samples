# Variables for the Azure Service Bus KEDA tutorial.
#
# Source this file from every script with: source ./00-variables.sh
# It first pulls in the values shared by the three KEDA tutorials (cluster, ACR, shared managed
# identity, scaling knobs), then adds the ones specific to this one.

# Variables
source ../../00-variables.sh

# Azure Service Bus. Real Azure (and the emulator) reject namespace names ending in -sb or -mgmt,
# and require between 6 and 50 characters.
SERVICE_BUS_NAMESPACE_NAME="${PREFIX}-servicebus-${SUFFIX}"
SERVICE_BUS_SKU="Standard"
SERVICE_BUS_QUEUE_NAME="work-items"
SERVICE_BUS_AUTHORIZATION_RULE="RootManageSharedAccessKey"

# The role the KEDA operator needs to read the queue's message count, granted on the namespace to
# the shared managed identity's principal id.
# https://learn.microsoft.com/en-us/azure/aks/keda-workload-identity
ROLE="Azure Service Bus Data Owner"

# Container images
PRODUCER_IMAGE_NAME="keda-servicebus-producer"
CONSUMER_IMAGE_NAME="keda-servicebus-consumer"

# Kubernetes. These names must match the ones in the YAML manifests in this folder.
NAMESPACE="keda-service-bus-sample"
CONFIG_MAP_NAME="sb-app-config"
SECRET_NAME="sb-connection"
DEPLOYMENT_NAME="sb-consumer"
PRODUCER_JOB_NAME="sb-producer"
TRIGGER_AUTHENTICATION_NAME="sb-trigger-auth"
SCALED_OBJECT_NAME="sb-scaler"
HPA_NAME="keda-hpa-${SCALED_OBJECT_NAME}"
