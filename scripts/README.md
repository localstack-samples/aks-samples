# Scripts

The scripts in this folder create the Azure Kubernetes Service (AKS) cluster that the [samples](../samples/) and [tutorials](../tutorials/) run on, and install optional add-ons into it. They work the same way against Azure and against the LocalStack for Azure emulator: see [Run against LocalStack](../README.md#run-against-localstack).

## Cluster scripts

Every cluster script creates the `local-aks-test` cluster in the `local-rg` resource group, together with the `localacrtest` container registry that every sample pushes its image to, attached to the cluster with `--attach-acr`. The scripts are idempotent: an existing resource is kept, so a script can be re-run after a failure.

| Script | Description | Features |
| ------ | ----------- | -------- |
| [01-basic-cluster.sh](01-basic-cluster.sh) | No questions: the smallest and fastest cluster to provision, for demos. To save time it turns off the Azure Files and Azure Disk CSI drivers and the CSI snapshot controller, so it runs every sample except [web-app-file-storage](../samples/web-app-file-storage/) and [web-app-in-cluster-postgresql](../samples/web-app-in-cluster-postgresql/). | System-assigned identity, Azure CNI Overlay with the Azure network policy, one node with the cluster autoscaler (1 to 3 nodes), Microsoft Entra Workload ID, Entra ID authentication with Azure RBAC (admin groups from `AAD_ADMIN_GROUP_OBJECT_IDS`), Advanced Container Networking Services (ACNS), container registry. Azure Files and Azure Disk CSI drivers and CSI snapshot controller off. |
| [01-configurable-cluster.sh](01-configurable-cluster.sh) | Asks which optional features to provision. Every question has a default and an environment variable, so the script also runs unattended. Pressing Enter at every question provisions the same features as the two scripts below. | Each feature of the scripts below can be turned off, plus the choice of cluster identity and network policy. Optionally installs NGINX Gateway Fabric and cert-manager. |
| [01-system-assigned-managed-identity.sh](01-system-assigned-managed-identity.sh) | The full, production-like cluster, with a system-assigned identity. The samples' CI uses it. | Custom virtual network with Azure Bastion, Key Vault with the CSI secrets provider, Container Insights, a user node pool across availability zones, cluster autoscaler, Workload ID, KEDA, managed Gateway API CRDs, Entra ID with Azure RBAC, ACNS, container registry. |
| [01-user-assigned-managed-identity.sh](01-user-assigned-managed-identity.sh) | The same full cluster with a pre-created user-assigned identity, which also gets the Contributor role on the node resource group. | As above, with a user-assigned identity. |

What the samples and tutorials need from the cluster:

- Workload ID: [web-app-managed-identity](../samples/web-app-managed-identity/), [web-app-app-configuration](../samples/web-app-app-configuration/), the KEDA tutorials under [tutorials/keda](../tutorials/keda/) and [tutorials/key-vault-csi-driver/workload-identity](../tutorials/key-vault-csi-driver/workload-identity/). The samples create their own workload identities and federated credentials when they are deployed.
- The Azure Files CSI driver: [web-app-file-storage](../samples/web-app-file-storage/), which mounts its file share through it.
- The Azure Disk CSI driver: [web-app-in-cluster-postgresql](../samples/web-app-in-cluster-postgresql/), whose database volume uses the `managed-csi-premium` storage class.
- The custom virtual network: [web-app-file-storage](../samples/web-app-file-storage/) in NFS mode only. Over SMB it works on any cluster with the Azure Files CSI driver.
- The Key Vault and the CSI secrets provider: nothing needs them from a cluster script. [tutorials/key-vault-csi-driver](../tutorials/key-vault-csi-driver/) creates its own vault and enables the add-on when they are missing.
- The Cilium network policy option (option 2 of the configurable script): the tutorials under [tutorials/policies/cilium](../tutorials/policies/cilium/). ACNS is always on, so they get Hubble and FQDN policies.
- NGINX Gateway Fabric, cert-manager and a public DNS zone: [web-app-managed-identity](../samples/web-app-managed-identity/) when it is deployed with `DEPLOY_GATEWAY=true`.

## Configurable script

### Questions and variables

Each question is skipped when its variable is set. Yes/no variables accept `true`, `false`, `yes`, `no`, `y` and `n`, in any case. Setting the variable of a question that is not asked, such as `CREATE_BASTION=true` with `CREATE_VNET=false`, is an error.

| Variable | Default | Effect |
| -------- | ------- | ------ |
| `CLUSTER_IDENTITY` | `system` | `system`, or `user` to create the `local-aks-identity-test` identity and assign it to the cluster. |
| `NETWORK_OPTION` | `1` | Azure CNI Overlay with `1` the Azure network policy, `2` the Cilium dataplane and network policy, `3` the Calico network policy. |
| `SYSTEM_NODE_COUNT` | `1` | Nodes in the `system` node pool. |
| `ENABLE_CLUSTER_AUTOSCALER` | `true` | The cluster autoscaler on both node pools, between 1 and 3 nodes (widened to include the node count). |
| `ENABLE_WORKLOAD_IDENTITY` | `true` | The OIDC issuer and Microsoft Entra Workload ID. |
| `CREATE_KEY_VAULT` | `true` | The `local-kv-test` vault, the `azure-keyvault-secrets-provider` add-on, and the Key Vault Administrator role for the add-on identity. |
| `ENABLE_MONITORING` | `true` | The `local-log-analytics-test` workspace and the `monitoring` add-on (Container Insights). |
| `ENABLE_FILE_CSI_DRIVER` | `true` | The Azure Files CSI driver and its `azurefile*` storage classes. `false` passes `--disable-file-driver`. |
| `ENABLE_DISK_CSI_DRIVER` | `true` | The Azure Disk CSI driver and its `managed-csi*` storage classes. `false` passes `--disable-disk-driver`. |
| `CREATE_VNET` | `true` | The `local-vnet-test` virtual network with `SystemSubnet`, plus `UserSubnet` when there is a user node pool, the Microsoft.Storage service endpoint on the node subnets, and the Network Contributor role for the cluster identity. Without it, AKS creates and manages the virtual network. |
| `CREATE_BASTION` | `true` | Asked only with the custom virtual network: `AzureBastionSubnet`, a public IP address and the `local-bastion-test` host. |
| `CREATE_USER_NODE_POOL` | `true` | The `user` node pool. |
| `USER_NODE_COUNT` | `1` | Asked only with the user node pool: its number of nodes. |
| `USE_AVAILABILITY_ZONES` | `true` | Asked only with the user node pool: spreads it across availability zones 1, 2 and 3. |
| `ENABLE_KEDA` | `true` | The KEDA add-on. |
| `ENABLE_GATEWAY_API` | `true` | The managed Gateway API CRDs (`--enable-gateway-api`). Needs azure-cli 2.86.0 or later, and no `aks-preview` extension. |
| `INSTALL_GATEWAY_CONTROLLERS` | `false` | Asked only with Gateway API: installs NGINX Gateway Fabric, which provides the `nginx` GatewayClass, and cert-manager with Helm. Needs `helm`. |
| `ENABLE_ENTRA_RBAC` | `true` | Microsoft Entra ID authentication with Azure RBAC for Kubernetes authorization. |
| `AAD_ADMIN_GROUP_OBJECT_IDS` | `<your-admin-group-object-id>` | Also read by `01-basic-cluster.sh`, which always enables Entra ID. Asked only with Entra ID: the comma-separated object IDs of the admin groups. The placeholder works on the emulator; on Azure, set real group object IDs. |
| `ASSUME_YES` | `false` | The same as `--yes`: skip the confirmation prompt. |
| `DRY_RUN` | `false` | The same as `--dry-run`. |

ACNS has no question: it is always on, as in the original scripts.

### Running unattended

When stdin is closed, every question that has no variable takes its default:

```bash
# Every default: the same features as the original scripts
./01-configurable-cluster.sh --yes </dev/null

# A light demo cluster: a user-assigned identity and Workload ID, nothing else optional
CLUSTER_IDENTITY=user ENABLE_CLUSTER_AUTOSCALER=false CREATE_KEY_VAULT=false ENABLE_MONITORING=false CREATE_VNET=false \
  CREATE_USER_NODE_POOL=false ENABLE_KEDA=false ENABLE_GATEWAY_API=false ENABLE_ENTRA_RBAC=false \
  ./01-configurable-cluster.sh --yes
```

### Dry run

`--dry-run` prints the configuration and then every command that a run against an empty resource group would execute, in order, without running any of them. It needs no `az login`, and values that a real run reads from Azure appear as placeholders such as `<system-subnet-id>`:

```bash
CREATE_VNET=false ./01-configurable-cluster.sh --dry-run </dev/null
```

`01-basic-cluster.sh` takes `--dry-run` and `--yes` too.

### Differences from the original scripts

With every default, the configurable script creates the same resources as the original scripts, with these differences:

- Automatic upgrades are off (`--auto-upgrade-channel none --node-os-upgrade-channel None`), so a demo cluster does not upgrade itself, and the Free tier is passed explicitly.
- No Windows administrator credentials are set, because the cluster has no Windows node pool.
- `~/.ssh/id_rsa.pub` is passed when it exists; without it, the cluster is created with `--no-ssh-key` instead of failing.
- The container registry, Log Analytics workspace, Key Vault and virtual network are created in parallel, and the Bastion host while the cluster is being created.
- The summary names the subscription the resources go to before asking to proceed, because the same command reaches Azure or the emulator depending on the Azure CLI configuration.
- A re-run keeps the Helm releases of NGINX Gateway Fabric and cert-manager that are already deployed instead of upgrading them.
- When the cluster already exists but was built with different answers, the script stops before creating anything and lists the differences, because most of them cannot be changed on an existing cluster.

## Add-on installers

Run these once the cluster is up.

| Script | Installs | Notes |
| ------ | -------- | ----- |
| [02-install-prometheus.sh](02-install-prometheus.sh) | The kube-prometheus-stack Helm chart in the `prometheus` namespace. | |
| [03-install-nginx-ingress-controller.sh](03-install-nginx-ingress-controller.sh) | The ingress-nginx controller in the `ingress-basic` namespace. | |
| [04-install-gateway-api.sh](04-install-gateway-api.sh) | The standard-channel Gateway API CRDs, v1.5.1, managed by you. | Do not run it on a cluster with the managed Gateway API CRDs: the original scripts and `01-configurable-cluster.sh` with its defaults install those. It suits `01-basic-cluster.sh` clusters. |
| [05-install-nginx-gateway-fabric.sh](05-install-nginx-gateway-fabric.sh) | NGINX Gateway Fabric, which creates the `nginx` GatewayClass. | Needs the Gateway API CRDs. `01-configurable-cluster.sh` installs it when `INSTALL_GATEWAY_CONTROLLERS=true`. |
| [06-install-cert-manager.sh](06-install-cert-manager.sh) | cert-manager with Gateway API support, and the `letsencrypt-nginx` ClusterIssuer for ingress-nginx. | `01-configurable-cluster.sh` installs cert-manager, without the ClusterIssuer, when `INSTALL_GATEWAY_CONTROLLERS=true`. |

[tutorials/gateway-api](../tutorials/gateway-api/) installs NGINX Gateway Fabric itself, so run it on a cluster created with `INSTALL_GATEWAY_CONTROLLERS=false`, the default.
