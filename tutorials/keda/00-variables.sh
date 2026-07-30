# Shared variables for the three KEDA tutorials (service-bus, queue-storage, event-hubs).
#
# Each tutorial's scripts/00-variables.sh sources this file with: source ../../00-variables.sh
#
# The AKS cluster is created by scripts/01-user-assigned-managed-identity.sh; these values MUST
# match that script (prefix "local", suffix "test", location "ItalyNorth") so the tutorials target
# the cluster it creates instead of standing up their own.

# Azure Kubernetes Service (AKS)
PREFIX="local"
SUFFIX="test"
AKS_NAME="${PREFIX}-aks-${SUFFIX}"
AKS_RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOCATION="ItalyNorth"

# Azure Container Registry. The tutorials build their producer and consumer images and push them
# here, exactly like the samples. The login server differs between targets (real Azure returns
# {name}.azurecr.io, the emulator returns {name}.azurecr.azure.localhost.localstack.cloud:4566),
# so it is always read at deploy time with `az acr show --query loginServer` and never hardcoded.
ACR_NAME="${PREFIX,,}acr${SUFFIX,,}"

# The single user-assigned managed identity shared by all three tutorials. The keda-operator
# service account exists once, in kube-system, so one shared identity lets the three tutorials
# coexist on the same cluster: whichever tutorial runs first creates the identity and annotates
# the operator, and the others find both already in place.
MANAGED_IDENTITY_NAME="${PREFIX}-keda-uami-${SUFFIX}"

# Federated identity credential that lets the KEDA operator exchange its projected service account
# token for a Microsoft Entra token. Subject and audience are fixed by the AKS tutorial:
# https://learn.microsoft.com/en-us/azure/aks/keda-workload-identity
FEDERATED_IDENTITY_NAME_KEDA="keda-operator"
FEDERATED_IDENTITY_AUDIENCE="api://AzureADTokenExchange"

# The KEDA add-on components, as installed by AKS in kube-system
KEDA_NAMESPACE="kube-system"
KEDA_OPERATOR_DEPLOYMENT="keda-operator"
KEDA_OPERATOR_SERVICE_ACCOUNT="keda-operator"
KEDA_SCALED_OBJECT_CRD="scaledobjects.keda.sh"

# Container images
IMAGE_TAG="v1"
IMAGE_PULL_POLICY="Always"

# Workload sizing. The producer sends MESSAGE_COUNT messages and each consumer sleeps
# WORK_SECONDS per message in batches of BATCH_SIZE, so a single activated replica cannot drain
# the backlog before the HPA observes the external metric. With a threshold of SCALING_THRESHOLD
# the HPA target is ceil(backlog / SCALING_THRESHOLD), capped at MAX_REPLICAS.
MESSAGE_COUNT=100
WORK_SECONDS=2
BATCH_SIZE=5
SCALING_THRESHOLD=5
MIN_REPLICAS=0
MAX_REPLICAS=4

# ScaledObject timing. The short polling interval and cooldown keep the scale-out and the
# scale-in observable inside a tutorial session; production values are usually much larger.
POLLING_INTERVAL=5
COOLDOWN_PERIOD=30
SCALE_DOWN_STABILIZATION_SECONDS=10

# How fast the autoscaler is allowed to add replicas. This is deliberately slower than the
# HorizontalPodAutoscaler default, which may add 4 pods (or double the count) every 15 seconds: with a
# backlog of MESSAGE_COUNT messages and a per-replica target of SCALING_THRESHOLD, the computed target
# is ceil(MESSAGE_COUNT / SCALING_THRESHOLD), far above MAX_REPLICAS, so the default policy would jump
# straight to the cap in a single step and there would be no ramp to watch. One replica per period
# makes the scale-out visible, which is the point of the sample. Scale-in is left aggressive, because
# once the backlog is gone there is nothing to be gradual about.
SCALE_UP_PODS=1
SCALE_UP_PERIOD_SECONDS=15

# The remaining fields of the ScaledObject's behavior block. They live here, and not in the manifests,
# so that every tuning knob comes from one place: 06-deploy-consumer.sh patches all of them with yq
# before applying scaledobject.yml, which means editing the manifest alone has no effect.
#
# A scale-up stabilization window of zero makes the autoscaler act on the newest metric rather than on
# the highest of the last few, so a spike is reacted to immediately. Scale-in stays aggressive: once
# the backlog is gone there is nothing to be gradual about, so the whole surplus may go in one period.
SCALE_UP_STABILIZATION_SECONDS=0
SCALE_DOWN_PERCENT=100
SCALE_DOWN_PERIOD_SECONDS=15

# Polling knobs used by the wait loops
TIMEOUT_SECONDS=300
SLEEP=5
RETRY_COUNT=5

# Azure Subscription and Tenant
TENANT_ID=$(az account show --query tenantId --output tsv --only-show-errors)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv --only-show-errors)
SUBSCRIPTION_ID=$(az account show --query id --output tsv --only-show-errors)
