# Variables for the Azure Storage Queue KEDA tutorial.
#
# Source this file from every script with: source ./00-variables.sh
# It first pulls in the values shared by the three KEDA tutorials (cluster, ACR, shared managed
# identity, scaling knobs), then adds the ones specific to this one.

# Variables. The shared file is located relative to THIS file, not to the working directory: a bare
# `source ../../00-variables.sh` resolves against $PWD, so it works only when the caller has already
# cd'd into this folder and fails for anything that sources this file by path from somewhere else.
source "$(dirname "${BASH_SOURCE[0]}")/../../00-variables.sh"

# Timings, overriding the shared defaults for this tutorial only.
#
# These have to live here rather than in scaledobject.yml: 06-deploy-consumer.sh patches the manifest
# with yq before applying it, so whatever pollingInterval, cooldownPeriod or scaleUp policy the YAML
# carries is replaced by the values below. Editing the manifest alone has no effect.
#
# The values are tuned to keep a live demonstration short. The scaler is asked for the queue depth
# every second, and the workload is deactivated ten seconds after the queue empties, so the round trip
# from zero to the ceiling and back fits in about a minute.
POLLING_INTERVAL=1
COOLDOWN_PERIOD=10
SCALE_DOWN_STABILIZATION_SECONDS=10
SCALE_UP_PERIOD_SECONDS=10

# The backlog has to outlast the climb. The autoscaler asks for ceil(backlog / SCALING_THRESHOLD)
# replicas, capped at MAX_REPLICAS, but it only adds one of them per SCALE_UP_PERIOD_SECONDS, so it
# reaches the ceiling only if MAX_REPLICAS * SCALING_THRESHOLD messages are still queued by the time
# it gets there. Too small a backlog drains while the ramp is still climbing and the deployment turns
# around before reaching the top. This many messages keep the consumer at the ceiling for about twenty
# seconds, and the round trip from zero and back takes about a minute.
MESSAGE_COUNT=80

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
