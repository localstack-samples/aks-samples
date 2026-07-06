# Azure Kubernetes Service (AKS) Samples

This repository contains a set of end-to-end samples that show how to deploy an [Azure Kubernetes Service (AKS)](https://learn.microsoft.com/en-us/azure/aks/what-is-aks) cluster and run a real workload on it, either against Azure in the cloud or locally on the [LocalStack for Azure](https://docs.localstack.cloud/azure/) emulator.

Every sample deploys the same Vacation Planner web app, a small Python [Flask](https://flask.palletsprojects.com/) single-page application, and only differs in the Azure data service used to persist the activity data behind it: 

- [Azure SQL Database](https://learn.microsoft.com/en-us/azure/azure-sql/database/sql-database-paas-overview?view=azuresql)
- [Azure Database DB for PostgreSQL flexible server](https://learn.microsoft.com/en-us/azure/postgresql/overview)
- An in-cluster [PostgreSQL](https://www.postgresql.org/) database deployed as a Kubernetes [StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Azure Cosmos DB for MongoDB](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/overview)
- [Azure Cosmos DB for NoSQL](https://learn.microsoft.com/en-us/azure/cosmos-db/overview)
- [Azure Blob Storage](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blobs-introduction)

This makes it easy to compare how the same application is wired up against different backing stores.

![Vacation Planner](images/vacation-planner.png)

## Prerequisites

- An [Azure subscription](https://azure.microsoft.com/free/) (for cloud deployments) or a running [LocalStack for Azure](https://docs.localstack.cloud/azure/) instance (for local deployments).
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`), authenticated with `az login`.
- [Docker](https://docs.docker.com/get-docker/) to build and run the container images.
- [kubectl](https://kubernetes.io/docs/tasks/tools/) to manage the cluster.
- [yq](https://github.com/mikefarah/yq), and (depending on the sample) `sqlcmd` or `psql` on the host machine.
- An SSH key pair at `~/.ssh/id_rsa.pub` (used to provision the AKS node pools).

> Running on LocalStack? Point the Azure CLI at the emulator endpoint (typically `http://localhost:4566`) and run the same scripts unchanged. The Azure resource model is emulated locally, so you can iterate on the full deployment without incurring cloud costs.

## Create an Azure Kubernetes Service (AKS) cluster

Before deploying any sample you must first provision an AKS cluster. Two interchangeable scripts are provided under [scripts/](scripts/); both produce an equivalent cluster and differ only in the type of managed identity assigned to the cluster:

| Script | Cluster identity | When to use |
| ------ | ---------------- | ----------- |
| [scripts/01-system-assigned-managed-identity.sh](scripts/01-system-assigned-managed-identity.sh) | System-assigned managed identity | Simplest option. Azure creates and manages the identity lifecycle together with the cluster. |
| [scripts/01-user-assigned-managed-identity.sh](scripts/01-user-assigned-managed-identity.sh) | User-assigned managed identity | Use when you need a stable, pre-created identity that can be reused across resources and granted role assignments ahead of time. |

Both scripts are idempotent: they check whether each resource already exists before creating it, so they can be safely re-run. They provision the following building blocks:

- A resource group and a Log Analytics workspace (wired to the cluster through the monitoring add-on / Azure Monitor for containers).
- A dedicated virtual network (`10.0.0.0/8`) with three subnets: `SystemSubnet` (system node pool), `UserSubnet` (user node pool), and `AzureBastionSubnet`.
- An [Azure Container Registry (ACR)](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-intro) that is attached to the cluster (via `--attach-acr`) so nodes can pull images without extra credentials.
- The AKS cluster itself, configured with:
  - An Azure CNI Overlay network plugin with the Azure network policy and data plane (pod CIDR `192.168.0.0/16`, service CIDR `172.16.0.0/16`).
  - A `system` node pool (in `SystemSubnet`) and a `user` node pool (`User` mode, in `UserSubnet`, spread across availability zones `1 2 3`), both with the cluster autoscaler enabled.
  - Azure Linux nodes using ephemeral OS disks for fast, low-latency node provisioning.
  - Microsoft Entra (Azure AD) integration with Azure RBAC, an admin group, OIDC issuer, and Workload Identity enabled, so workloads can authenticate to Azure services without secrets.
  - The Gateway API add-on enabled.

The `01-user-assigned-managed-identity.sh` script additionally creates a user-assigned managed identity, assigns it to the cluster (`--assign-identity`), and grants it the Contributor role on the node resource group and the Network Contributor role on the virtual network. The system-assigned variant grants Network Contributor on the virtual network to the auto-created cluster identity.

Both scripts finish by running `az aks get-credentials`, which merges the cluster context into your local `kubeconfig` so `kubectl` is ready to use.

> Edit the variables at the top of the chosen script (`prefix`, `suffix`, `location`, node sizes, `aad_profile_admin_group_object_ids`, and so on) to match your environment before running it.

```bash
cd scripts
./01-system-assigned-managed-identity.sh   # or ./01-user-assigned-managed-identity.sh
```

The [scripts/](scripts/) folder also contains optional add-on installers you can run once the cluster is up, for example [02-install-prometheus.sh](scripts/02-install-prometheus.sh), [03-install-nginx-ingress-controller.sh](scripts/03-install-nginx-ingress-controller.sh), [04-install-gateway-api.sh](scripts/04-install-gateway-api.sh), [05-install-nginx-gateway-fabric.sh](scripts/05-install-nginx-gateway-fabric.sh), and [06-install-cert-manager.sh](scripts/06-install-cert-manager.sh).

## Samples

To run any sample you must first create the AKS cluster with one of the two scripts above. Then pick a sample from the [samples/](samples/) folder and run the numbered scripts in its `samples/<sample>/scripts` folder in order. The web app source code for each sample lives in `samples/<sample>/src`.

All samples implement the same Vacation Planner web app. They only vary the underlying repository where the activity data is actually stored.

| Sample | Description |
| ------ | ----------- |
| [web-app-sql-database](samples/web-app-sql-database/) | Stores activities in an [Azure SQL Database](https://learn.microsoft.com/en-us/azure/azure-sql/database/sql-database-paas-overview), connecting with a SQL login over TDS. |
| [web-app-mysql-flexible-server](samples/web-app-mysql-flexible-server/) | Stores activities in an [Azure Database for MySQL flexible server](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/overview). |
| [web-app-postgresql-flexible-server](samples/web-app-postgresql-flexible-server/) | Stores activities in an [Azure Database for PostgreSQL flexible server](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/overview). |
| [web-app-in-cluster-postgresql](samples/web-app-in-cluster-postgresql/) | Stores activities in an in-cluster [PostgreSQL](https://www.postgresql.org/) database deployed as a Kubernetes [StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) (a primary with two streaming-replica standbys), instead of a managed Azure data service. |
| [web-app-cosmosdb-mongodb-api](samples/web-app-cosmosdb-mongodb-api/) | Stores activities in a collection of an [Azure Cosmos DB for MongoDB](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/introduction) account. |
| [web-app-cosmosdb-nosql-api](samples/web-app-cosmosdb-nosql-api/) | Stores activities in a container of an [Azure Cosmos DB for NoSQL](https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/) account. |
| [web-app-storage-account](samples/web-app-storage-account/) | Stores activities in an [Azure Blob Storage](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blobs-introduction) container, using a connection string. |
| [web-app-managed-identity](samples/web-app-managed-identity/) | Stores activities in an Azure Blob Storage container, authenticating with [Microsoft Entra Workload ID](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview) (federated credential plus workload identity) instead of a secret, and optionally exposes the app through the Gateway API with a managed TLS certificate. |
| [key-vault-csi-driver](samples/key-vault-csi-driver/) | Mounts secrets from [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/overview) into a pod with the [Azure Key Vault provider for Secrets Store CSI Driver](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver), demonstrating both the Microsoft Entra Workload ID and the user-assigned managed identity access modes. |

Each sample folder follows the same layout:

```
samples/<sample>/
├── README.md       # sample-specific documentation
├── scripts/        # numbered deployment scripts + Kubernetes manifests
└── src/            # Flask web app source code
```

### Accessing the Vacation Planner web app

Each sample exposes the web app through a Kubernetes `ClusterIP` service, which is only reachable from inside the cluster. To open the app from your machine, port-forward the service to a local port with `kubectl`:

```bash
# Generic form: replace <namespace> and <service> with the sample's values
kubectl port-forward service/<service> 8080:80 -n <namespace>
```

Then browse to [http://localhost:8080](http://localhost:8080). The exact namespace and service name for each sample are documented in its own `README.md`.

Alternatively, you can use a terminal UI such as [k9s](https://k9scli.io/) to select the service and start a port-forward interactively (press `<shift-f>` on a selected service or pod).

## Tutorials

Beyond the Vacation Planner samples, the repository includes standalone tutorials that exercise specific AKS capabilities. Unlike the samples above, they do not deploy the web app.

| Tutorial | Description |
| ------ | ----------- |
| [policies](policies/) | Kubernetes network policy tutorials that enforce zero-trust traffic control with [Calico](https://docs.tigera.io/calico/latest/about/) and [Cilium](https://docs.cilium.io/): cluster-wide default-deny, DNS-aware (FQDN) egress, and L3/L4/L7 ingress. |
| [ccm](ccm/scripts/) | Exercises the [Azure cloud controller manager](https://cloud-provider-azure.sigs.k8s.io/) load-balancer reconcile on the emulator: public and internal `Service` type `LoadBalancer`, `loadBalancerSourceRanges` NSG rules, the nodeIP backend-pool variant, and an NGINX ingress controller. |

## Tools

The following tools are useful when working with these samples:

| Tool | Description |
| ---- | ----------- |
| [kubectl](https://kubernetes.io/docs/reference/kubectl/) ([repo](https://github.com/kubernetes/kubectl)) | The official Kubernetes command-line client for inspecting and managing cluster resources. |
| [k9s](https://k9scli.io/) ([repo](https://github.com/derailed/k9s)) | A terminal UI to observe, navigate, and manage Kubernetes clusters in real time. |
| [kubecm](https://kubecm.cloud/) ([repo](https://github.com/sunny0826/kubecm)) | A command-line tool to add, merge, switch, and clean up entries across multiple `kubeconfig` files. |
| [kubectx + kubens](https://github.com/ahmetb/kubectx) | Companion tools to quickly switch between clusters (`kubectx`) and namespaces (`kubens`). |
| [yq](https://mikefarah.gitbook.io/yq/) ([repo](https://github.com/mikefarah/yq)) | A portable command-line YAML, JSON, and XML processor, used by the deployment scripts to template the manifests. |
| [Helm](https://helm.sh/) ([repo](https://github.com/helm/helm)) | The package manager for Kubernetes, used by the add-on installers to deploy charts. |
| [Helm Dashboard](https://github.com/komodorio/helm-dashboard) | A web UI to browse installed Helm releases, inspect their manifests, and review revision history. |
| [Lens](https://k8slens.dev/) ([repo](https://github.com/lensapp/lens)) | A graphical desktop IDE for working with Kubernetes clusters. |
| [kustomize](https://kustomize.io/) ([repo](https://github.com/kubernetes-sigs/kustomize)) | A template-free way to customize and overlay Kubernetes manifests. |
| [stern](https://github.com/stern/stern) | A command-line tool for tailing logs across multiple pods and containers at once. |
| [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/) ([repo](https://github.com/Azure/azure-cli)) | The command-line tool for creating and managing Azure resources. |
| [Azure Storage Explorer](https://learn.microsoft.com/en-us/azure/storage/storage-explorer/vs-azure-tools-storage-manage-with-storage-explorer?tabs=windows) | A graphical desktop tool to browse and manage blobs, tables, queues, and files in Azure Storage accounts. |
| [LocalStack for Azure](https://docs.localstack.cloud/azure/) ([repo](https://github.com/localstack/localstack)) | A cloud service emulator that runs the Azure resource model locally for development and testing. |

## Training Courses 
This section contains links to useful free training courses. 

### Microsoft | Learn

- [Browse all training](https://learn.microsoft.com/en-us/training/browse/) (if you are curious to see the available training courses)
- [Introduction to Kubernetes](https://learn.microsoft.com/en-us/training/modules/intro-to-kubernetes/)
- [Introduction to Azure Kubernetes Service](https://learn.microsoft.com/en-us/training/modules/intro-to-azure-kubernetes-service/)
- [Implement Azure Container Apps](https://learn.microsoft.com/en-us/training/modules/implement-azure-container-apps/)
- [Deploy a containerized application on Azure Kubernetes Service](https://learn.microsoft.com/en-us/training/modules/aks-deploy-container-app/)

### The Linux Foundation

- [Kubernetes and Cloud Native Essentials (LFS250)](https://training.linuxfoundation.org/training/kubernetes-and-cloud-native-essentials-lfs250/)
- [Introduction to Kubernetes (LFS158)](https://training.linuxfoundation.org/training/introduction-to-kubernetes/)

### Kubernetes Documentation

- [Learn Kubernetes Basics](https://kubernetes.io/docs/tutorials/kubernetes-basics/)