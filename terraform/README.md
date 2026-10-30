# Terraform Deployment

This directory contains Terraform modules and a deployment script that create the same Azure Kubernetes Service (AKS) cluster as [scripts/01-system-assigned-managed-identity.sh](../scripts/01-system-assigned-managed-identity.sh) or, with `identity_type` set to `UserAssigned`, as [scripts/01-user-assigned-managed-identity.sh](../scripts/01-user-assigned-managed-identity.sh): the same resources, with the same names and defaults, including the [diagnostic settings](../scripts/README.md#monitoring). Every [sample](../samples/) runs on it. For the samples and the other ways to create the cluster, see the [README](../README.md) at the root of the repository.

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/), or an Azure subscription
- [Terraform](https://developer.hashicorp.com/terraform/downloads) (1.9+)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) + [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/), and on Azure [kubelogin](https://learn.microsoft.com/en-us/azure/aks/kubelogin-authentication) (`az aks install-cli` installs both)

```bash
brew install localstack/tap/lstk   # or: npm install -g @localstack/lstk
```

## Architecture Overview

The Terraform configuration uses two providers: [azurerm](https://registry.terraform.io/providers/hashicorp/azurerm/latest) 5.10.0 for every Azure resource, and [AzAPI](https://registry.terraform.io/providers/Azure/azapi/latest) 2.13.0 for the managed Gateway API only, which azurerm does not expose. It provisions:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli) `local-rg`.
2. [Azure Log Analytics Workspace](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview) `local-log-analytics-test` (module `log_analytics`), `PerGB2018` pricing tier, with a system-assigned identity.
3. [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/overview) `local-kv-test` (module `key_vault`) with Azure RBAC authorization.
4. [Azure Container Registry](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-intro) `localacrtest` (module `container_registry`), Basic SKU, with the admin user enabled. Every sample pushes its image to it.
5. [Azure Virtual Network](https://learn.microsoft.com/azure/virtual-network/virtual-networks-overview) `local-vnet-test` (module `virtual_network`), `10.0.0.0/8`, with three subnets:
   - *SystemSubnet* (`10.240.0.0/16`) and *UserSubnet* (`10.241.0.0/16`) for the two node pools, both with the `Microsoft.Storage` service endpoint that the NFS volumes of the Azure Files CSI driver need.
   - *AzureBastionSubnet* (`10.242.2.0/24`) for the Bastion host.
6. [Azure Bastion](https://learn.microsoft.com/en-us/azure/bastion/bastion-overview) `local-bastion-test` (module `bastion_host`), Basic SKU, with its Standard, static public IP address `local-bastion-ip-test`.
7. With `identity_type` set to `UserAssigned`, the [user-assigned managed identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview) `local-aks-identity-test` of the cluster.
8. The AKS cluster `local-aks-test` (module `aks_cluster`):
   - The latest GA Kubernetes version in the region, which `deploy.sh` looks up as the scripts do.
   - The `system` node pool on *SystemSubnet*: `Standard_D4ds_v5` nodes with Azure Linux and a 50 GB ephemeral OS disk, one node with the cluster autoscaler between 1 and 3, 100 pods per node.
   - Azure CNI Overlay, with the network policy and dataplane of the scripts' menu option (`network_option`), pod CIDR `192.168.0.0/16`, service CIDR `172.16.0.0/16`, DNS service IP `172.16.0.10`, and [Advanced Container Networking Services](https://learn.microsoft.com/en-us/azure/aks/advanced-container-networking-services-overview).
   - Microsoft Entra ID with Azure RBAC, the OIDC issuer and [Microsoft Entra Workload ID](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview).
   - The `monitoring` add-on (Container Insights) with its `MSCI-<location>-local-aks-test` data collection rule and association, and the Key Vault secrets provider add-on.
   - KEDA, the Azure Files and Azure Disk CSI drivers and the CSI snapshot controller.
9. The `user` node pool (module `aks_node_pool`) on *UserSubnet*, with the same node settings as the system pool, spread across availability zones 1, 2 and 3.
10. The managed Gateway API CRDs (`azapi_update_resource`), ordered after the user node pool because AKS serializes the operations on a cluster.
11. The role assignments of the scripts: Network Contributor on the virtual network and on *SystemSubnet* for the cluster identity (the second is what `az aks create --vnet-subnet-id` grants), Key Vault Administrator on the key vault for the identity of the Key Vault secrets provider add-on, and AcrPull on the registry for the kubelet identity (what `az aks create --attach-acr` grants). AKS itself grants the cluster identity the Contributor role on the node resource group, which the user-assigned script checks for.
12. A diagnostic setting called `default` on the cluster, the virtual network, the public IP address, the Bastion host, the registry and the key vault, inside each resource's module, which sends its logs and metrics to the workspace. See [Monitoring](../scripts/README.md#monitoring) for the log categories.

### Provider configuration: emulator and Azure

[`providers.tf`](providers.tf) hardcodes no endpoint and no subscription: every setting is a variable that defaults to `null`, which targets Azure with the Azure CLI credentials. `deploy.sh` checks which cloud the Azure CLI targets and, when it is the emulator that `lstk az start-interception` configures, passes:

| Variable | Value |
| -------- | ----- |
| `metadata_host` | `localhost.localstack.cloud:4566`, from which azurerm discovers every endpoint |
| `resource_manager_endpoint` | `az cloud show --query endpoints.resourceManager`, for AzAPI, which has no metadata discovery |
| `subscription_id`, `tenant_id`, `client_id`, `client_secret` | The emulator's placeholder credentials |
| `gateway_api_enabled` | `false`, see [LocalStack emulator notes](#localstack-emulator-notes) |

Against Azure, `deploy.sh` passes only `subscription_id`, from `az account show`, and both providers authenticate with the Azure CLI session.

## Provisioning Script

[`deploy.sh`](deploy.sh) performs:

1. Detection of the target, the emulator or Azure, from the active Azure CLI cloud.
2. Lookup of the latest GA Kubernetes version in the region.
3. `terraform init`, `terraform validate`, `terraform plan` and `terraform apply`, with the variables below.
4. On the emulator only, `az aks update --enable-gateway-api`.
5. `az aks get-credentials`, to configure `kubectl` for the cluster.
6. Printing the cluster's storage profile and storage classes, as the scripts do.

```bash
# the cluster of scripts/01-system-assigned-managed-identity.sh
./deploy.sh

# the cluster of scripts/01-user-assigned-managed-identity.sh, with the Cilium dataplane and network policy
IDENTITY_TYPE=UserAssigned NETWORK_OPTION=2 ./deploy.sh
```

Then deploy the samples as their READMEs describe, as on a cluster created by the scripts.

## Variables

[`terraform.tfvars`](terraform.tfvars) holds the scripts' defaults. `deploy.sh` passes the variables below with `-var`, from environment variables that default to the scripts' values. The scripts ask for the network option and the node counts; here they come from the environment:

| Environment variable | Terraform variable | Default | Script variable |
| -------------------- | ------------------ | ------- | --------------- |
| `PREFIX` | `prefix` | `local` | `prefix` |
| `SUFFIX` | `suffix` | `test` | `suffix` |
| `LOCATION` | `location` | `italynorth` | `location` |
| `IDENTITY_TYPE` | `identity_type` | `SystemAssigned` | The choice of script |
| `NETWORK_OPTION` | `network_option` | `1` | The network plugin and policy menu: `1` Azure CNI Overlay with the Azure network policy, `2` with the Cilium dataplane and network policy, `3` with the Calico network policy |
| `SYSTEM_NODE_COUNT` | `system_node_count` | `1` | `node_count`, asked by the scripts |
| `USER_NODE_COUNT` | `user_node_count` | `1` | `node_pool_node_count`, asked by the scripts |
| `AAD_ADMIN_GROUP_OBJECT_IDS` | `aad_admin_group_object_ids` | None | `aad_profile_admin_group_object_ids` |
| `SSH_PUBLIC_KEY_FILE` | `ssh_public_key`, the file's content | `~/.ssh/id_rsa.pub` | `ssh_key_value` |
| `WINDOWS_ADMIN_PASSWORD` | `windows_admin_password` | The scripts' password | `windows_admin_password` |
| | `kubernetes_version` | The latest GA version in the region | `kubernetes_version` |

The cluster differs from the scripts' in what azurerm adds: it sends the Azure Policy add-on as disabled, and adds the `enableRetinaNetworkFlags` setting, `false`, to the monitoring add-on. It requests the observability of Advanced Container Networking Services and, only with the Cilium dataplane (network option 2), their security features, which is what AKS turns on for `az aks create --enable-acns`.

The autoscaler range of each node pool is 1 to 3 nodes, widened to include the node count, as in the scripts. azurerm accepts only GUIDs as admin group object IDs, so where the scripts pass the placeholder `<your-admin-group-object-id>`, the default here is no admin group; on Azure, set `AAD_ADMIN_GROUP_OBJECT_IDS` to the comma-separated object IDs of real Microsoft Entra ID groups. The registry and key vault names are globally unique on Azure, so export your own `SUFFIX` there.

## Verification

```bash
# the diagnostic settings of the cluster's resources
../tests/test-diagnostic-settings.sh

# the cluster and its node pools
terraform output
az aks nodepool list --cluster-name local-aks-test --resource-group local-rg \
  --query "[].{name: name, mode: mode, count: count, zones: availabilityZones}" --output table
kubectl get nodes
```

## LocalStack emulator notes

- The emulator does not persist the managed Gateway API from AzAPI's PUT, so on the emulator `deploy.sh` passes `gateway_api_enabled=false` and enables the Gateway API with `az aks update --enable-gateway-api` after the apply.
- The emulator does not return the Windows profile, and azurerm replaces a cluster to change one, so the configuration ignores changes to the Windows profile, as it does to the node counts the cluster autoscaler manages.
- On the emulator, a cluster the scripts create reports the security features of Advanced Container Networking Services as enabled even with the Azure dataplane, which those features do not support; the cluster Terraform creates reports them as disabled.

## Related Documentation

- [azurerm_kubernetes_cluster](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster)
- [azurerm_monitor_diagnostic_setting](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting)
- [Monitor AKS: resource logs](https://learn.microsoft.com/en-us/azure/aks/monitor-aks#azure-monitor-resource-logs)
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
