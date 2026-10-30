# Bicep Deployment

This directory contains the Bicep template and a deployment script that create the same Azure Kubernetes Service (AKS) cluster as [scripts/01-system-assigned-managed-identity.sh](../scripts/01-system-assigned-managed-identity.sh) or, with `identityType` set to `UserAssigned`, as [scripts/01-user-assigned-managed-identity.sh](../scripts/01-user-assigned-managed-identity.sh): the same resources, with the same names and defaults, including the [diagnostic settings](../scripts/README.md#monitoring). Every [sample](../samples/) runs on it. For the samples and the other ways to create the cluster, see the [README](../README.md) at the root of the repository.

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/), or an Azure subscription
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli), which installs Bicep on first use, and the [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/), and on Azure [kubelogin](https://learn.microsoft.com/en-us/azure/aks/kubelogin-authentication) (`az aks install-cli` installs both)
- [Visual Studio Code](https://code.visualstudio.com/) + [Bicep extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep), optional

```bash
brew install localstack/tap/lstk   # or: npm install -g @localstack/lstk
```

## Architecture Overview

The [`deploy.sh`](deploy.sh) script creates the `local-rg` resource group, while the Bicep modules create:

1. [Azure Log Analytics Workspace](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview) (`log-analytics.bicep`) `local-log-analytics-test`, `PerGB2018` pricing tier, with a system-assigned identity.
2. [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/overview) (`key-vault.bicep`) `local-kv-test` with Azure RBAC authorization.
3. [Azure Container Registry](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-intro) (`container-registry.bicep`) `localacrtest`, Basic SKU, with the admin user enabled. Every sample pushes its image to it.
4. [Azure Virtual Network](https://learn.microsoft.com/azure/virtual-network/virtual-networks-overview) (`virtual-network.bicep`) `local-vnet-test`, `10.0.0.0/8`, with three subnets:
   - *SystemSubnet* (`10.240.0.0/16`) and *UserSubnet* (`10.241.0.0/16`) for the two node pools, both with the `Microsoft.Storage` service endpoint that the NFS volumes of the Azure Files CSI driver need.
   - *AzureBastionSubnet* (`10.242.2.0/24`) for the Bastion host.
5. [Azure Bastion](https://learn.microsoft.com/en-us/azure/bastion/bastion-overview) (`bastion-host.bicep`) `local-bastion-test`, Basic SKU, with its Standard, static public IP address `local-bastion-ip-test`.
6. With `identityType` set to `UserAssigned`, the [user-assigned managed identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview) `local-aks-identity-test` of the cluster (`managed-identity.bicep`).
7. The AKS cluster `local-aks-test` (`aks-cluster.bicep`):
   - The latest GA Kubernetes version in the region, which `deploy.sh` looks up as the scripts do.
   - The `system` node pool on *SystemSubnet*: `Standard_D4ds_v5` nodes with Azure Linux and a 50 GB ephemeral OS disk, one node with the cluster autoscaler between 1 and 3, 100 pods per node.
   - Azure CNI Overlay, with the network policy and dataplane of the scripts' menu option (`networkOption`), pod CIDR `192.168.0.0/16`, service CIDR `172.16.0.0/16`, DNS service IP `172.16.0.10`, and [Advanced Container Networking Services](https://learn.microsoft.com/en-us/azure/aks/advanced-container-networking-services-overview).
   - Microsoft Entra ID with Azure RBAC, the OIDC issuer and [Microsoft Entra Workload ID](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview).
   - The `monitoring` add-on (Container Insights) with its `MSCI-<location>-local-aks-test` data collection rule and association, and the Key Vault secrets provider add-on.
   - The managed Gateway API CRDs, KEDA, the Azure Files and Azure Disk CSI drivers and the CSI snapshot controller.
8. The `user` node pool (`aks-node-pool.bicep`) on *UserSubnet*, with the same node settings as the system pool, spread across availability zones 1, 2 and 3.
9. The role assignments of the scripts: Network Contributor on the virtual network and on *SystemSubnet* for the cluster identity (the second is what `az aks create --vnet-subnet-id` grants), Key Vault Administrator on the key vault for the identity of the Key Vault secrets provider add-on, and AcrPull on the registry for the kubelet identity (what `az aks create --attach-acr` grants). AKS itself grants the cluster identity the Contributor role on the node resource group, which the user-assigned script checks for.
10. A diagnostic setting called `default` on the cluster, the virtual network, the public IP address, the Bastion host, the registry and the key vault, inside each resource's module, which sends its logs and metrics to the workspace. See [Monitoring](../scripts/README.md#monitoring) for the log categories.

## Configuration

[`main.bicepparam`](main.bicepparam) holds the scripts' defaults:

```bicep
using 'main.bicep'

param prefix = 'local'
param suffix = 'test'
param identityType = 'SystemAssigned'
param networkOption = 1
param systemNodeCount = 1
param userNodeCount = 1
param nodeVmSize = 'Standard_D4ds_v5'
param osSku = 'AzureLinux'
param osDiskSizeGB = 50
param osDiskType = 'Ephemeral'
param maxPods = 100
param windowsAdminUsername = 'azadmin'

param windowsAdminPassword = readEnvironmentVariable('WINDOWS_ADMIN_PASSWORD')
```

`deploy.sh` passes the parameters below on the command line, from environment variables that default to the scripts' values. The scripts ask for the network option and the node counts; here they come from the environment:

| Environment variable | Parameter | Default | Script variable |
| -------------------- | --------- | ------- | --------------- |
| `PREFIX` | `prefix` | `local` | `prefix` |
| `SUFFIX` | `suffix` | `test` | `suffix` |
| `LOCATION` | `location` | `italynorth` | `location` |
| `IDENTITY_TYPE` | `identityType` | `SystemAssigned` | The choice of script |
| `NETWORK_OPTION` | `networkOption` | `1` | The network plugin and policy menu: `1` Azure CNI Overlay with the Azure network policy, `2` with the Cilium dataplane and network policy, `3` with the Calico network policy |
| `SYSTEM_NODE_COUNT` | `systemNodeCount` | `1` | `node_count`, asked by the scripts |
| `USER_NODE_COUNT` | `userNodeCount` | `1` | `node_pool_node_count`, asked by the scripts |
| `AAD_ADMIN_GROUP_OBJECT_IDS` | `aadAdminGroupObjectIds` | `<your-admin-group-object-id>` | `aad_profile_admin_group_object_ids` |
| `SSH_PUBLIC_KEY_FILE` | `sshPublicKey`, the file's content | `~/.ssh/id_rsa.pub` | `ssh_key_value` |
| `WINDOWS_ADMIN_PASSWORD` | `windowsAdminPassword` | The scripts' password | `windows_admin_password` |
| | `kubernetesVersion` | The latest GA version in the region | `kubernetes_version` |

The autoscaler range of each node pool is 1 to 3 nodes, widened to include the node count, as in the scripts. The admin group placeholder works on the emulator; on Azure, set `AAD_ADMIN_GROUP_OBJECT_IDS` to the comma-separated object IDs of real Microsoft Entra ID groups. The registry and key vault names are globally unique on Azure, so export your own `SUFFIX` there.

## Deployment

```bash
# the cluster of scripts/01-system-assigned-managed-identity.sh
./deploy.sh

# the cluster of scripts/01-user-assigned-managed-identity.sh, with the Cilium dataplane and network policy
IDENTITY_TYPE=UserAssigned NETWORK_OPTION=2 ./deploy.sh

# preview the changes of a re-deployment instead of validating the template
USE_WHAT_IF=1 ./deploy.sh
```

The script will:

1. Look up the latest GA Kubernetes version in the region.
2. Ensure the resource group exists.
3. Validate `main.bicep` (or run a what-if with `USE_WHAT_IF=1`; `VALIDATE_TEMPLATE=0` skips both).
4. Deploy the template, passing the parameters above.
5. Configure `kubectl` for the cluster with `az aks get-credentials`.
6. Print the cluster's storage profile and storage classes, as the scripts do.

Then deploy the samples as their READMEs describe, as on a cluster created by the scripts.

## Verification

```bash
# the diagnostic settings of the cluster's resources
../tests/test-diagnostic-settings.sh

# the cluster and its node pools
az aks show --name local-aks-test --resource-group local-rg \
  --query "{identity: identity.type, network: networkProfile.networkPolicy, gatewayApi: ingressProfile}" --output json
az aks nodepool list --cluster-name local-aks-test --resource-group local-rg \
  --query "[].{name: name, mode: mode, count: count, zones: availabilityZones}" --output table
kubectl get nodes
```

## LocalStack emulator notes

The template deploys on the emulator as it is, and the cluster it creates there matches the one the scripts create: the same resources, cluster settings, node pools, role assignments and diagnostic settings. As for a cluster the scripts create, the emulator does not return the Windows profile.

## Related Documentation

- [Microsoft.ContainerService managedClusters (Bicep)](https://learn.microsoft.com/en-us/azure/templates/microsoft.containerservice/managedclusters)
- [Microsoft.Insights diagnosticSettings (Bicep)](https://learn.microsoft.com/en-us/azure/templates/microsoft.insights/diagnosticsettings)
- [Monitor AKS: resource logs](https://learn.microsoft.com/en-us/azure/aks/monitor-aks#azure-monitor-resource-logs)
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
