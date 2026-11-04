# Variables for the GPU node pools tutorial.
#
# Source this file from every script with: source ./00-variables.sh
#
# The AKS cluster is created by scripts/01-user-assigned-managed-identity.sh; these values MUST match that script
# (prefix "local", suffix "test", location "ItalyNorth") so the tutorial adds its GPU node pool to the cluster it
# creates instead of standing up its own.

# Azure Kubernetes Service (AKS)
PREFIX="local"
SUFFIX="test"
AKS_NAME="${PREFIX}-aks-${SUFFIX}"
AKS_RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOCATION="ItalyNorth"

# The Spot GPU node pool. Standard_NV18ads_A10_v5 runs half an NVIDIA A10 GPU, which Kubernetes sees as one
# nvidia.com/gpu, with 18 vCPUs. Spot VMs count against the region's Spot vCPU quota (lowPriorityCores) whatever their
# VM family, and Azure starts one only when it has Spot capacity. Check the quota with:
#   az vm list-usage --location italynorth --query "[?name.value=='lowPriorityCores']" --output table
# The pool starts with no node: the cluster autoscaler adds one when a pod asks for a GPU and removes it when it is idle.
GPU_NODE_POOL_NAME="gpupool"
GPU_NODE_VM_SIZE="Standard_NV18ads_A10_v5"
GPU_NODE_OS_SKU="AzureLinux"
GPU_NODE_MIN_COUNT=0
GPU_NODE_MAX_COUNT=1
GPU_NODE_PRIORITY="Spot"
GPU_NODE_EVICTION_POLICY="Delete"
# -1 pays up to the on-demand price, so Azure evicts the node when it needs the capacity back, never for its price
GPU_NODE_SPOT_MAX_PRICE=-1
# The jobs select the pool's nodes by this label, and only pods that tolerate this taint run on them
GPU_NODE_LABEL_KEY="workload"
GPU_NODE_LABEL_VALUE="gpu"
GPU_NODE_TAINT_KEY="sku"
GPU_NODE_TAINT_VALUE="gpu"
# AKS adds this label and this NoSchedule taint to every node of a Spot node pool
SPOT_KEY="kubernetes.azure.com/scalesetpriority"
SPOT_VALUE="spot"
# AKS labels the nodes of NVIDIA GPU VM sizes with it, and the device plugin DaemonSet selects them by it
GPU_NODE_ACCELERATOR_LABEL="accelerator=nvidia"

# The NVIDIA device plugin DaemonSet, from Microsoft's guide to installing it by hand. AKS installs the NVIDIA driver
# on the GPU nodes, and the plugin advertises their GPUs to Kubernetes as nvidia.com/gpu.
DEVICE_PLUGIN_NAMESPACE="gpu-resources"
DEVICE_PLUGIN_NAME="nvidia-device-plugin-daemonset"
DEVICE_PLUGIN_IMAGE="nvcr.io/nvidia/k8s-device-plugin:v0.18.0"

# Azure Service Bus. Namespace names are global on Azure, between 6 and 50 characters, and can't end in -sb or -mgmt.
SERVICE_BUS_NAMESPACE_NAME="${PREFIX}-gpu-servicebus-${SUFFIX}"
SERVICE_BUS_SKU="Standard"
SERVICE_BUS_QUEUE_NAME="training-requests"
SERVICE_BUS_AUTHORIZATION_RULE="RootManageSharedAccessKey"
# The role the KEDA operator needs to read the queue's message count, and the job to receive a message, granted on the
# namespace to the managed identity's principal id. https://learn.microsoft.com/en-us/azure/aks/keda-workload-identity
ROLE="Azure Service Bus Data Owner"

# The user-assigned managed identity the KEDA operator and the training job sign in with. It is the identity of the KEDA
# tutorials: the keda-operator service account exists once, in kube-system, and is bound to one identity, so sharing it
# lets this tutorial and the KEDA ones run on the same cluster. Whichever runs first creates it and binds the operator.
MANAGED_IDENTITY_NAME="${PREFIX}-keda-uami-${SUFFIX}"
FEDERATED_IDENTITY_AUDIENCE="api://AzureADTokenExchange"
FEDERATED_IDENTITY_NAME_KEDA="keda-operator"
FEDERATED_IDENTITY_NAME_JOB="gpu-training-job"
KEDA_NAMESPACE="kube-system"
KEDA_OPERATOR_DEPLOYMENT="keda-operator"
KEDA_OPERATOR_SERVICE_ACCOUNT="keda-operator"
KEDA_SCALED_JOB_CRD="scaledjobs.keda.sh"

# The training job. KEDA's ScaledJob creates one Kubernetes Job for each message on the queue. The job's pod asks for
# one GPU, receives one message with workload identity, reads how many seconds to train from it, and trains a small
# PyTorch model on the GPU when PyTorch finds one, on the CPU otherwise. The image is the official PyTorch runtime with
# CUDA, about 3 GB; the pod installs the Service Bus and identity libraries when it starts.
NAMESPACE="gpu-training"
SERVICE_ACCOUNT_NAME="gpu-training"
SCRIPT_CONFIG_MAP_NAME="gpu-training-script"
TRIGGER_AUTHENTICATION_NAME="gpu-training-trigger-auth"
SCALED_JOB_NAME="gpu-training"
JOB_IMAGE="pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime"
# websocket-client: with a custom endpoint address, which the emulator needs (see functions.sh), the Python Service Bus
# library uses AMQP over WebSockets, and that transport needs websocket-client. On Azure the job doesn't load it.
JOB_PYTHON_PACKAGES="azure-servicebus==7.13.0 azure-identity==1.19.0 websocket-client==1.9.2"
JOB_CPU_REQUEST="1"
JOB_MEMORY_REQUEST="2Gi"
JOB_MEMORY_LIMIT="4Gi"
JOB_BACKOFF_LIMIT=3
# Seconds the job trains when its message doesn't say
JOB_DEFAULT_TRAIN_SECONDS=60
SCALED_JOB_POLLING_INTERVAL=10
SCALED_JOB_MAX_REPLICAS=2

# The two runs of the tutorial: a short job, and a long one whose Spot node is evicted while it trains
FIRST_JOB_TRAIN_SECONDS=60
EVICTED_JOB_TRAIN_SECONDS=600

# Waits poll every POLL_INTERVAL seconds and give up after their timeout, in seconds. On Azure a Spot GPU node takes a
# few minutes to start and to install the NVIDIA driver, and the PyTorch image takes a few minutes to pull.
POLL_INTERVAL=10
JOB_START_TIMEOUT=1800
JOB_TIMEOUT=2400
NODE_DELETION_TIMEOUT=900
