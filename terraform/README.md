# Terraform Deployment

This directory contains Terraform modules and a deployment script that create the same Azure Kubernetes Service (AKS) cluster as [scripts/01-system-assigned-managed-identity.sh](../scripts/01-system-assigned-managed-identity.sh) or, with `identity_type` set to `UserAssigned`, as [scripts/01-user-assigned-managed-identity.sh](../scripts/01-user-assigned-managed-identity.sh): the same resources, with the same names and defaults, including the [diagnostic settings](../scripts/README.md#monitoring). Every [sample](../samples/) runs on it. For the samples and the other ways to create the cluster, see the [README](../README.md) at the root of the repository.

## Architecture

![Architecture of the AKS cluster](../images/aks-cluster-architecture.png)

[scripts/01-user-assigned-managed-identity.sh](../scripts/01-user-assigned-managed-identity.sh) deploys the AKS cluster that the [samples](../samples/) and [tutorials](../tutorials/) run on, together with the network, container registry, key vault and monitoring around it. [scripts/01-system-assigned-managed-identity.sh](../scripts/01-system-assigned-managed-identity.sh), [scripts/01-configurable-cluster.sh](../scripts/01-configurable-cluster.sh) with every default, and the [Bicep](../bicep/) and [Terraform](./) deployments create the same architecture. The Bicep and Terraform deployments use a user-assigned identity when `identityType` (Bicep) or `identity_type` (Terraform) is `UserAssigned`. With a system-assigned identity, Azure creates the cluster identity (item 6) together with the cluster. The architecture is composed of the following Azure resources:

1. [Azure Resource Group](https://learn.microsoft.com/azure/azure-resource-manager/management/manage-resource-groups-cli) `<prefix>-rg`: A logical container scoping the resources below. AKS creates a second one for the cluster's infrastructure, the node resource group (item 10).
2. [Azure Key Vault](https://learn.microsoft.com/azure/key-vault/general/overview) `<prefix>-kv-<suffix>` with the [Azure RBAC permission model](https://learn.microsoft.com/azure/key-vault/general/rbac-guide): A vault whose secrets pods can mount as files through the [Azure Key Vault Secrets Provider](https://learn.microsoft.com/azure/aks/csi-secrets-store-driver) add-on. The add-on's identity (item 10) holds [Key Vault Administrator](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/security#key-vault-administrator) on it. No sample needs it: [tutorials/key-vault-csi-driver](../tutorials/key-vault-csi-driver/) creates its own vault.
3. [Azure Log Analytics workspace](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview) `<prefix>-log-analytics-<suffix>` (`PerGB2018` pricing tier, system-assigned identity): Stores the [Container Insights](https://learn.microsoft.com/azure/azure-monitor/containers/container-insights-overview) data of the cluster, such as the `ContainerLogV2`, `KubeEvents` and `KubePodInventory` tables, and the resource logs and metrics that [diagnostic settings](https://learn.microsoft.com/azure/azure-monitor/essentials/diagnostic-settings) named `default` send from the cluster, the virtual network, the Bastion host and its public IP address, the registry and the key vault. See [Monitoring](../scripts/README.md#monitoring).
4. [Azure Virtual Network](https://learn.microsoft.com/azure/virtual-network/virtual-networks-overview) `<prefix>-vnet-<suffix>` (`10.0.0.0/8`): Hosts three subnets:
   - *SystemSubnet* (`10.240.0.0/16`): The nodes of the system node pool.
   - *UserSubnet* (`10.241.0.0/16`): The nodes of the user node pool.
   - *AzureBastionSubnet* (`10.242.2.0/24`): The Bastion host.

   The two node subnets have the `Microsoft.Storage` [service endpoint](https://learn.microsoft.com/azure/virtual-network/virtual-network-service-endpoints-overview), so that in NFS mode the storage account of [web-app-file-storage](../samples/web-app-file-storage/) can accept traffic from the nodes only.
5. [Azure Bastion](https://learn.microsoft.com/azure/bastion/bastion-overview) `<prefix>-bastion-<suffix>` (Basic SKU), with the Standard static [public IP address](https://learn.microsoft.com/azure/virtual-network/ip-services/public-ip-addresses) `<prefix>-bastion-ip-<suffix>`: Reaches the nodes over SSH from the Azure portal, without exposing them to the internet.
6. [User-assigned managed identity](https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/overview) `<prefix>-aks-identity-<suffix>`: The [cluster identity](https://learn.microsoft.com/azure/aks/use-managed-identity), which the control plane uses to manage the cluster's Azure resources. It is created before the cluster and assigned to it. It holds [Network Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/networking#network-contributor) on the virtual network and on *SystemSubnet*, which a cluster in a custom virtual network needs, and [Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/privileged#contributor) on the node resource group, which AKS grants.
7. [Azure Container Registry](https://learn.microsoft.com/azure/container-registry/container-registry-intro) `<prefix>acr<suffix>` (Basic SKU, admin user enabled): Stores the container images of the samples. It is [attached to the cluster](https://learn.microsoft.com/azure/aks/cluster-container-registry-integration): the kubelet identity (item 10) holds the [AcrPull](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/containers#acrpull) role on it, so the nodes pull the images without credentials.
8. [Azure Kubernetes Service (AKS) cluster](https://learn.microsoft.com/azure/aks/what-is-aks) `<prefix>-aks-<suffix>`, on the newest generally available Kubernetes version of the region:
   - [Azure CNI Overlay](https://learn.microsoft.com/azure/aks/azure-cni-overlay) networking: the nodes take their addresses from the subnets, the pods from `192.168.0.0/16` outside the virtual network, and the services from `172.16.0.0/16`, with the cluster DNS service at `172.16.0.10`. The [network policy](https://learn.microsoft.com/azure/aks/use-network-policies) is Azure, Cilium (with the Cilium data plane) or Calico, as chosen in the scripts' menu, the `networkOption` parameter in Bicep or the `network_option` variable in Terraform.
   - [Microsoft Entra ID authentication](https://learn.microsoft.com/azure/aks/enable-authentication-microsoft-entra-id) with [Azure RBAC for Kubernetes authorization](https://learn.microsoft.com/azure/aks/manage-azure-rbac): the members of the cluster's admin groups are cluster administrators, and any other user or identity needs an Azure Kubernetes Service RBAC role, such as Azure Kubernetes Service RBAC Cluster Admin. `kubectl` signs in with [kubelogin](https://learn.microsoft.com/azure/aks/kubelogin-authentication).
   - The [OIDC issuer](https://learn.microsoft.com/azure/aks/use-oidc-issuer) and [Microsoft Entra Workload ID](https://learn.microsoft.com/azure/aks/workload-identity-overview): a pod signs in to Azure services as a managed identity through a federated credential, without secrets. The samples that need it create their own identities and credentials.
   - Add-ons and features: Container Insights (the `monitoring` add-on), the Azure Key Vault Secrets Provider, [KEDA](https://learn.microsoft.com/azure/aks/keda-about), the [managed Gateway API](https://learn.microsoft.com/azure/aks/managed-gateway-api) CRDs, [Advanced Container Networking Services](https://learn.microsoft.com/azure/aks/advanced-container-networking-services-overview), and the [Azure Disk](https://learn.microsoft.com/azure/aks/azure-disk-csi) and [Azure Files](https://learn.microsoft.com/azure/aks/azure-files-csi) CSI drivers with the snapshot controller.
9. [Node pools](https://learn.microsoft.com/azure/aks/create-node-pools): the [system node pool](https://learn.microsoft.com/azure/aks/use-system-pools) `system` in *SystemSubnet*, created with the cluster, and the user node pool `user` in *UserSubnet*, spread across [availability zones](https://learn.microsoft.com/azure/aks/availability-zones) 1, 2 and 3. Both run [Azure Linux](https://learn.microsoft.com/azure/azure-linux/intro-azure-linux) on `Standard_D4ds_v5` virtual machines with 50 GiB [ephemeral OS disks](https://learn.microsoft.com/azure/aks/concepts-storage#ephemeral-os-disks-in-aks), up to 100 pods per node, and the [cluster autoscaler](https://learn.microsoft.com/azure/aks/cluster-autoscaler-overview) between 1 and 3 nodes.
10. [Node resource group](https://learn.microsoft.com/azure/aks/faq#why-are-two-resource-groups-created-with-aks-) `MC_<prefix>-rg_<prefix>-aks-<suffix>_<location>`, created and managed by AKS: Holds the virtual machine scale sets of the two node pools, the [Standard load balancer](https://learn.microsoft.com/azure/aks/load-balancer-standard) `kubernetes` with the public IP address of the cluster's outbound traffic, the network security group of the nodes, and the disks and storage accounts that the CSI drivers create for persistent volumes. It also holds two user-assigned managed identities: the kubelet identity `<prefix>-aks-<suffix>-agentpool`, which pulls the images from the registry (item 7), and `azurekeyvaultsecretsprovider-<prefix>-aks-<suffix>`, the identity of the Key Vault Secrets Provider (item 2).
11. [Data collection rule](https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-overview) `MSCI-<location>-<prefix>-aks-<suffix>`, in the resource group, with its association to the cluster: Tells the Container Insights agent on the nodes what to collect, and sends the data to the workspace (item 3). The monitoring add-on creates it for the scripts; the Bicep and Terraform templates define it themselves.

Every deployment ends with `az aks get-credentials`, which merges the cluster into your kubeconfig. Each sample then pushes its image to the registry and deploys into its own namespace: the nodes pull the image through the kubelet identity, the samples that use Workload ID reach Azure services without secrets, and the logs of every pod land in the `ContainerLogV2` table of the workspace, where the KQL queries in the sample READMEs read them.

In this directory, [`main.tf`](main.tf) creates the resource group (item 1), the user-assigned identity (item 6, with `identity_type` set to `UserAssigned`), the role assignments, and the managed Gateway API CRDs, which it enables with AzAPI after the user node pool because AKS serializes the operations on a cluster. The modules create the other resources: `log_analytics` (item 3), `key_vault` (item 2), `container_registry` (item 7), `virtual_network` (item 4), `bastion_host` (item 5), `aks_cluster` (item 8 with the `system` node pool, and item 11) and `aks_node_pool` (the `user` node pool). Each module also creates the `default` diagnostic settings of its resources.

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/), or an Azure subscription
- [Terraform](https://developer.hashicorp.com/terraform/downloads) (1.9+)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) + [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/), and on Azure [kubelogin](https://learn.microsoft.com/en-us/azure/aks/kubelogin-authentication) (`az aks install-cli` installs both)

```bash
brew install localstack/tap/lstk   # or: npm install -g @localstack/lstk
```

## Provider configuration: emulator and Azure

The Terraform configuration uses two providers: [azurerm](https://registry.terraform.io/providers/hashicorp/azurerm/latest) 5.10.0 for every Azure resource, and [AzAPI](https://registry.terraform.io/providers/Azure/azapi/latest) 2.13.0 for the managed Gateway API only, which azurerm does not expose.

[`providers.tf`](providers.tf) hardcodes no endpoint and no subscription: every setting is a variable that defaults to `null`, which targets Azure with the Azure CLI credentials. `deploy.sh` checks which cloud the Azure CLI targets and, when it is the emulator that `lstk az start-interception` configures, passes:

| Variable | Value |
| -------- | ----- |
| `metadata_host` | The host and port of the Resource Manager endpoint the Azure CLI targets (`azure.localhost.localstack.cloud:4566` with lstk), from which azurerm discovers every endpoint |
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
| `LOCATION` | `location` | `westeurope` | `location` |
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
- Earlier versions of the emulator do not return the Windows profile, and azurerm replaces a cluster to change one, so the configuration ignores changes to the Windows profile, as it does to the node counts the cluster autoscaler manages.
- On the emulator, a cluster the scripts create reports the security features of Advanced Container Networking Services as enabled even with the Azure dataplane, which those features do not support; the cluster Terraform creates reports them as disabled.

## Related Documentation

- [azurerm_kubernetes_cluster](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster)
- [azurerm_monitor_diagnostic_setting](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting)
- [Monitor AKS: resource logs](https://learn.microsoft.com/en-us/azure/aks/monitor-aks#azure-monitor-resource-logs)
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
