# Variables

# Azure Resources
PREFIX='zeus'
SUFFIX='test'
LOCATION='italynorth'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
ACR_NAME="${PREFIX,,}acr${SUFFIX,,}"
ACR_SKU='Standard'
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
TENANT_ID=$(az account show --query tenantId --output tsv)
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

# In-cluster PostgreSQL (deployed via statefulset.yml)
PG_PORT='5432'
PG_USER_NAME='testuser'
PG_USER_PASSWORD='TestP@ssw0rd123'
PG_DATABASE_NAME='PlannerDB'

# StatefulSet topology and write/read endpoints (see statefulset.yml).
# The app does writes, so it must target the primary (write) endpoint.
PG_STATEFULSET_NAME='pg-postgres'
PG_PRIMARY_POD='pg-postgres-0'
PG_PRIMARY_SERVICE='pg-postgres-primary'

# Superuser bootstrap credentials. These MUST match the POSTGRES_PASSWORD in the
# pg-postgres-secret defined in statefulset.yml — keep both in sync if changed.
PG_SUPERUSER='postgres'
PG_SUPERUSER_PASSWORD='SuperStrongPass123'

# Local port used by `kubectl port-forward` to reach the in-cluster DB from the
# host (scripts 03 and 06).
PG_LOCAL_PORT='5432'

# Application config — must match the seed-row `username` in 06-create-test-data.sh.
# PostgreSQL `=` is case-sensitive (unlike SQL Server), so this stays lowercase.
LOGIN_NAME='paolo'

# Docker Image
IMAGE_NAME="vacation-planner-postgres"
IMAGE_PULL_POLICY="Always"
IMAGE_TAG="v1"
PORT="8080"

# Kubernetes
NAMESPACE="vacation-planner-postgres"
DEPLOYMENT_NAME="vacation-planner-postgres"
SERVICE_NAME="vacation-planner-postgres"
CONFIGMAP_NAME="vacation-planner-postgres-config"
K8S_SECRET_NAME="vacation-planner-postgres-secrets"
