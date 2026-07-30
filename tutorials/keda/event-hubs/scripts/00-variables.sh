# Variables for the Azure Event Hubs KEDA tutorial.
#
# Source this file from every script with: source ./00-variables.sh
# It first pulls in the values shared by the three KEDA tutorials (cluster, ACR, shared managed
# identity, scaling knobs), then adds the ones specific to this one.

# Variables
source ../../00-variables.sh

# Timings, overriding the shared defaults for this tutorial only.
#
# These have to live here rather than in scaledobject.yml: 06-deploy-consumer.sh patches the manifest
# with yq before applying it, so whatever pollingInterval, cooldownPeriod or scaleUp policy the YAML
# carries is replaced by the values below. Editing the manifest alone has no effect.
#
# The values are tuned to keep a live demonstration short. The scaler is asked for the lag every
# second, and the workload is deactivated ten seconds after the lag reaches zero, so the round trip
# from zero to the ceiling and back fits in about a minute.
POLLING_INTERVAL=1
COOLDOWN_PERIOD=10
SCALE_DOWN_STABILIZATION_SECONDS=10
SCALE_UP_PERIOD_SECONDS=10

# The backlog has to outlast the climb. The scaler clamps the lag it reports to
# EVENT_HUB_PARTITION_COUNT * SCALING_THRESHOLD, so the autoscaler asks for the full partition count
# as long as at least that many events are outstanding, but it only adds one replica per
# SCALE_UP_PERIOD_SECONDS. Too small a backlog drains while the ramp is still climbing and the
# deployment turns around before reaching the top. This many events keep the consumer at the ceiling
# for about twenty seconds, and the round trip from zero and back takes about a minute.
MESSAGE_COUNT=80

# Azure Event Hubs. Real Azure (and the emulator) require the namespace name to be between 6 and 50
# characters. The Standard SKU is the lowest one that supports more than one consumer group.
EVENT_HUBS_NAMESPACE_NAME="${PREFIX}-eventhubs-${SUFFIX}"
EVENT_HUBS_SKU="Standard"
EVENT_HUB_NAME="events"

# The partitions of the hub are the unit of parallelism: Event Hubs gives each partition to one
# consumer at a time, so no more than this many consumer replicas receive events concurrently.
EVENT_HUB_PARTITION_COUNT=4

# The consumer group whose checkpoints the scaler reads. A dedicated one keeps the sample's cursor
# separate from the $Default group any other reader may be using.
EVENT_HUB_CONSUMER_GROUP="keda-cg"

# The authorization rule is created on the event hub, not on the namespace, so the connection string
# it returns carries EntityPath=<hub>. That is what tells the KEDA scaler which hub to read without
# any extra trigger metadata.
EVENT_HUB_AUTHORIZATION_RULE="keda-consumer"

# Storage account holding the consumer group's checkpoints. Storage account names must be 3 to 24
# characters, lowercase letters and digits only, hence the ,, lowercasing expansions.
STORAGE_ACCOUNT_NAME="${PREFIX,,}kedaeh${SUFFIX,,}"
STORAGE_ACCOUNT_SKU="Standard_LRS"
STORAGE_ACCOUNT_KIND="StorageV2"
CHECKPOINT_CONTAINER="eh-checkpoints"

# The roles the shared managed identity is granted. They are not exercised by this tutorial, which
# authenticates the scaler and the applications with connection strings, but they are what a reader
# running against real Azure needs to switch the trigger over to workload identity.
# https://learn.microsoft.com/en-us/azure/event-hubs/authenticate-application
EVENT_HUBS_ROLE="Azure Event Hubs Data Owner"
STORAGE_ROLE="Storage Blob Data Contributor"

# Container images
PRODUCER_IMAGE_NAME="keda-eventhub-producer"
CONSUMER_IMAGE_NAME="keda-eventhub-consumer"

# Kubernetes. These names must match the ones in the YAML manifests in this folder.
NAMESPACE="keda-event-hubs-sample"
CONFIG_MAP_NAME="eh-app-config"
SECRET_NAME="eh-connection"
DEPLOYMENT_NAME="eh-consumer"
PRODUCER_JOB_NAME="eh-producer"
SCALED_OBJECT_NAME="eh-scaler"
HPA_NAME="keda-hpa-${SCALED_OBJECT_NAME}"
