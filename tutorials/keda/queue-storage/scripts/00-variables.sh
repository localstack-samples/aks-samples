# Variables for the Azure Storage Queue KEDA tutorial.
#
# Source this file from every script with: source ./00-variables.sh
# It first pulls in the values shared by the three KEDA tutorials (cluster, ACR, shared managed
# identity, scaling knobs), then adds the ones specific to this one.

# Variables
source ../../00-variables.sh

# Azure Storage. A storage account name must be 3 to 24 characters long and contain lowercase letters
# and numbers only, hence the lowercase expansion of the shared prefix and suffix.
# https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules
STORAGE_ACCOUNT_NAME="${PREFIX,,}kedaqueue${SUFFIX,,}"
STORAGE_ACCOUNT_SKU="Standard_LRS"
STORAGE_ACCOUNT_KIND="StorageV2"
STORAGE_QUEUE_NAME="jobs"

# The role granted on the storage account to the shared managed identity's principal id. The same
# identity is used by the KEDA scaler, which reads the queue's message count, and by the producer and
# consumer applications, which add, read, and delete messages, so it needs the contributor role rather
# than the reader one.
# https://learn.microsoft.com/en-us/azure/storage/queues/assign-azure-role-data-access
ROLE="Storage Queue Data Contributor"

# Microsoft Entra Workload ID for the applications. Unlike the other two KEDA tutorials, the producer
# and the consumer authenticate with the same managed identity as the scaler, through their own
# service account and their own federated identity credential, so no connection string and no account
# key is ever created. https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview
SERVICE_ACCOUNT_NAME="queue-app"
FEDERATED_IDENTITY_NAME_APP="queue-app"

# Container images
PRODUCER_IMAGE_NAME="keda-queue-producer"
CONSUMER_IMAGE_NAME="keda-queue-consumer"

# Kubernetes. These names must match the ones in the YAML manifests in this folder. There is no
# secret: the applications hold no credential.
NAMESPACE="keda-queue-storage-sample"
CONFIG_MAP_NAME="queue-app-config"
DEPLOYMENT_NAME="queue-consumer"
PRODUCER_JOB_NAME="queue-producer"
TRIGGER_AUTHENTICATION_NAME="queue-trigger-auth"
SCALED_OBJECT_NAME="queue-scaler"
HPA_NAME="keda-hpa-${SCALED_OBJECT_NAME}"
