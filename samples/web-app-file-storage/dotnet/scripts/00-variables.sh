# Variables

# Azure Resources
PREFIX='local'
SUFFIX='test'
LOCATION='italynorth'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
ACR_NAME="${PREFIX,,}acr${SUFFIX,,}"
ACR_SKU='Standard'
AKS_CLUSTER_NAME="${PREFIX}-aks-${SUFFIX}"
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
TENANT_ID=$(az account show --query tenantId --output tsv)
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Storage Accounts
# An SMB share needs a general-purpose v2 account, an NFS share needs a premium FileStorage account
# (NFS Azure file shares are only available on SSD file shares), and the kind of an account cannot be
# changed after creation. Each protocol therefore gets its own account, so switching protocol never
# collides with the account created for the other one.
SMB_STORAGE_ACCOUNT_NAME="${PREFIX}filesmb${SUFFIX}"
SMB_STORAGE_ACCOUNT_KIND='StorageV2'
SMB_STORAGE_ACCOUNT_SKU='Standard_LRS'
NFS_STORAGE_ACCOUNT_NAME="${PREFIX}filenfs${SUFFIX}"
NFS_STORAGE_ACCOUNT_KIND='FileStorage'
NFS_STORAGE_ACCOUNT_SKU='Premium_LRS'

# Azure file share
FILE_SHARE_NAME='activities'
# A premium file share is provisioned storage with a 100 GiB minimum, so both protocols use the same
# size to keep a single PersistentVolumeClaim for all the combinations.
FILE_SHARE_QUOTA_GB='100'

# Docker Image
IMAGE_NAME="vacation-planner-file-dotnet"
IMAGE_PULL_POLICY="Always"
IMAGE_TAG="v1"
PORT="8080"

# Kubernetes
NAMESPACE="vacation-planner-file"
DEPLOYMENT_NAME="vacation-planner-file"
SERVICE_NAME="vacation-planner-file"
CONFIGMAP_NAME="vacation-planner-file-config"
SEED_CONFIGMAP_NAME="vacation-planner-file-seed"
SECRET_NAME="vacation-planner-file-secrets"
STORAGE_SECRET_NAME="vacation-planner-file-storage"
PERSISTENT_VOLUME_NAME="vacation-planner-file-pv"
PERSISTENT_VOLUME_CLAIM_NAME="vacation-planner-file-pvc"

# Storage class used to provision the volume on demand.
# SMB uses azurefile-csi, one of the four azurefile* classes the Azure Files CSI driver installs on
# every AKS cluster. NFS needs a class of its own, because none of the built-in ones sets
# protocol: nfs, and it is created by 05-deploy-app.sh from storageclass-nfs.yml.
SMB_STORAGE_CLASS_NAME='azurefile-csi'
NFS_STORAGE_CLASS_NAME="vacation-planner-file-nfs"

# Directory where the Azure file share is mounted in the pods
ACTIVITIES_DIR='/data'

# Deployment options chosen interactively in 01-deploy-resources.sh, or exported beforehand for an
# unattended run. The generated file assigns each value with ${VAR:-value} syntax, so an exported
# environment variable always takes precedence over the persisted choice.
DEPLOY_OPTIONS_FILE="$CURRENT_DIR/.deploy-options.env"
[ -f "$DEPLOY_OPTIONS_FILE" ] && source "$DEPLOY_OPTIONS_FILE"
PROVISIONING_MODE="${PROVISIONING_MODE:-}"
FILE_SHARE_PROTOCOL="${FILE_SHARE_PROTOCOL:-}"
