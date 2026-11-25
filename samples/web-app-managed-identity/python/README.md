# Vacation Planner: Azure Blob Storage with Microsoft Entra Workload ID

> A .NET version of this sample lives in [../dotnet](../dotnet/README.md).

This sample demonstrates a Python Flask single-page web application called *Vacation Planner* hosted on an [Azure Kubernetes Service (AKS)](https://learn.microsoft.com/en-us/azure/aks/what-is-aks) cluster in the cloud on Azure or locally in the LocalStack emulator for Azure. The app runs in a dedicated namespace and stores activity data in the `activities` container of an [Azure Blob Storage](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blobs-introduction) account.

Unlike the [`web-app-blob-storage`](../../web-app-blob-storage/python/) sample, which uses a connection string, this sample authenticates to the storage account without any secret, using [Microsoft Entra Workload ID](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview). A [user-assigned managed identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview) is federated with a Kubernetes service account, so the pod obtains Microsoft Entra tokens through the cluster's OIDC issuer and accesses the storage account with its RBAC role assignment.

Optionally, when `DEPLOY_GATEWAY="true"` in [`00-variables.sh`](scripts/00-variables.sh), the sample also exposes the app on a public hostname through the [Gateway API](https://gateway-api.sigs.k8s.io/), with an A record created in an [Azure DNS](https://learn.microsoft.com/en-us/azure/dns/dns-overview) zone and a TLS certificate issued via [cert-manager](https://cert-manager.io/).

Before installing the sample, make sure to create an [Azure Kubernetes Service (AKS)](https://learn.microsoft.com/en-us/azure/aks/what-is-aks) cluster by using one of the following scripts:

- [scripts/01-system-assigned-managed-identity.sh](../../../scripts/01-system-assigned-managed-identity.sh): creates the cluster using a system-assigned managed identity as its cluster identity.
- [scripts/01-user-assigned-managed-identity.sh](../../../scripts/01-user-assigned-managed-identity.sh): creates the cluster using a user-assigned managed identity as its cluster identity.

Both scripts enable the OIDC issuer and workload identity that this sample relies on. If you enable the Gateway path, also install the [Gateway API](https://gateway-api.sigs.k8s.io/) and [cert-manager](https://cert-manager.io/) add-ons from the root `scripts/` folder. All commands below are run from this sample's `scripts/` folder.

> **Running on LocalStack?** Install the [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/) and run `lstk az start-interception` to route Azure CLI calls to the emulator. See [Run against LocalStack](../../../README.md#run-against-localstack) for the full setup.

## Architecture

The following diagram illustrates the architecture of the solution:

![Architecture Diagram](./images/architecture.png)

## Deployment workflow

Run the numbered scripts in order from the `scripts/` folder:

```bash
cd scripts
./01-deploy-resources.sh
./02-build-docker-image.sh
./03-run-docker-container.sh   # optional local smoke test
./04-push-docker-image.sh
./05-deploy-app.sh
```

## Scripts and manifests

| File | Description |
| ---- | ----------- |
| [`00-variables.sh`](scripts/00-variables.sh) | Defines the variables shared across the other scripts (resource names, image tag, managed identity and federated credential names, storage account, optional DNS/Gateway settings, Kubernetes namespace, …). The other scripts load these values by sourcing this file. |
| [`01-deploy-resources.sh`](scripts/01-deploy-resources.sh) | Deploys the Azure resources used by this sample: the resource group, the [Azure Container Registry (ACR)](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-intro), the [Azure Blob Storage](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blobs-introduction) account and `activities` container with three sample activities (one blob each, uploaded only when missing), and the [user-assigned managed identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview) with its role assignment on the storage account. |
| [`02-build-docker-image.sh`](scripts/02-build-docker-image.sh) | Builds the Docker image for the web app from the [`src/`](src/) folder. |
| [`03-run-docker-container.sh`](scripts/03-run-docker-container.sh) | Runs the web app in a local Docker container (no Kubernetes) to validate that it starts and connects to the storage account as expected. |
| [`04-push-docker-image.sh`](scripts/04-push-docker-image.sh) | Tags and pushes the Docker image to the Azure Container Registry, on Azure or in the LocalStack emulator. |
| [`05-deploy-app.sh`](scripts/05-deploy-app.sh) | Creates the workload-identity service account and the [federated identity credential](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation) that links it to the managed identity, then uses the YAML manifests below (templated with `yq`) to deploy the app. When `DEPLOY_GATEWAY="true"`, it also applies the Issuer, Gateway, and HTTPRoute and updates the [Azure DNS](https://learn.microsoft.com/en-us/azure/dns/dns-overview) A record. |
| [`Dockerfile`](scripts/Dockerfile) | Builds the Docker image of the web app. |
| [`namespace.yml`](scripts/namespace.yml) | Creates the Kubernetes namespace. |
| [`configmap.yml`](scripts/configmap.yml) | Creates the ConfigMap holding non-secret input values (blob container name, storage account URL, managed identity client ID, tenant ID) passed to the app as environment variables. |
| [`secret.yml`](scripts/secret.yml) | Creates the Secret holding sensitive values (the Flask secret key, and the optional connection string / client secret fallback) passed to the app as environment variables. |
| [`deployment.yml`](scripts/deployment.yml) | Creates the Kubernetes Deployment, including the pod specification and the workload-identity service account reference. The liveness and readiness probes call `GET /health`. |
| [`service.yml`](scripts/service.yml) | Creates the `ClusterIP` Service that exposes the web app inside the cluster. |
| [`issuer.yml`](scripts/issuer.yml) | (Gateway path) cert-manager Issuer that solves the ACME HTTP-01 challenge through a Gateway API HTTPRoute. |
| [`gateway.yml`](scripts/gateway.yml) | (Gateway path) Gateway API Gateway that exposes the app on the configured public hostname. |
| [`httproute.yml`](scripts/httproute.yml) | (Gateway path) Gateway API HTTPRoute that routes the hostname's traffic to the Service. |

## Accessing the web app

By default the app is exposed through a `ClusterIP` service, which is only reachable from inside the cluster. Port-forward it to a local port to open it from your machine:

```bash
kubectl port-forward service/vacation-planner-identity 8080:80 -n vacation-planner-identity
```

Then browse to [http://localhost:8080](http://localhost:8080). Alternatively, use a tool such as [k9s](https://k9scli.io/) to start the port-forward interactively.

The app also exposes `GET /health`, the endpoint the liveness and readiness probes call: it returns `{"status": "ok"}` when the blob container is reachable and `503` with `{"status": "unavailable"}` otherwise.

```bash
curl http://localhost:8080/health
```

If you deployed the Gateway path (`DEPLOY_GATEWAY="true"`), the app is instead reachable directly at the public hostname configured in [`00-variables.sh`](scripts/00-variables.sh) (`https://<subdomain>.<dns-zone>`), with no port-forward required.

## Logs

The app logs one line per request — gunicorn writes an access log line for every call, the probes included, because its command passes `--access-logfile -` — plus one line per blob read, uploaded or deleted and one line for every activity added, updated, deleted or retrieved (see [Query the logs with KQL](#query-the-logs-with-kql)). Every entry carries a timestamp, the logger name and the level; the Azure SDK and `urllib3` stay at warning level. The [.NET version](../dotnet/README.md) writes the same trace.

```bash
kubectl logs deployment/vacation-planner-identity -n vacation-planner-identity --tail=50
```

## Query the logs with KQL

The cluster scripts listed at the top of this page enable the monitoring add-on, so Container Insights collects the containers' logs and the cluster's inventory, events and metrics in the Log Analytics workspace they create (`local-log-analytics-test` in `local-rg`, with the default names). The [Bicep](../../../bicep/README.md) and [Terraform](../../../terraform/README.md) templates enable it too, and [scripts/01-configurable-cluster.sh](../../../scripts/01-configurable-cluster.sh) enables it unless you turn monitoring off. [scripts/01-basic-cluster.sh](../../../scripts/01-basic-cluster.sh) doesn't.

To explore the data, open the Log Analytics workspace in the [Azure Portal Emulator](https://docs.localstack.cloud/azure/developer-tools/portal/) or in the Azure portal, select **Logs** in the navigation bar, and run queries written in the [Kusto Query Language (KQL)](https://docs.localstack.cloud/azure/developer-tools/kusto-query-language/). On Azure, new rows can take a few minutes to arrive. The same queries run from the command line through the Azure CLI's `log-analytics` extension (`az extension add --name log-analytics`):

```bash
workspace_id=$(az monitor log-analytics workspace show \
  --resource-group local-rg \
  --workspace-name local-log-analytics-test \
  --query customerId \
  --output tsv)

az monitor log-analytics query \
  --workspace "$workspace_id" \
  --analytics-query 'ContainerLogV2 | where LogMessage has "Activity" | take 20' \
  --output table
```

Container Insights writes these tables:

- **ContainerLogV2**: Recommended table (replacing the legacy ContainerLog) containing the stdout and stderr logs emitted by containers. It offers improved schemas and support for multi-line logs.
- **KubeEvents**: Collects native Kubernetes events generated within the cluster (e.g., pod scheduling, crashes, restarts).
- **KubePodInventory**: Information about the status and lifecycle of the cluster's pods (Ready, Failed, Pending, etc.).
- **ContainerInventory**: Tracks the status of individual containers (e.g., images used, execution status, container ID).
- **ContainerNodeInventory**: Information and status of the worker nodes (VMs or VMSSs) that make up the node pools.
- **InsightsMetrics**: Metrics about deployments, the kubelets and scraped Prometheus endpoints. On Azure it also holds the nodes' disk and network metrics, which the emulator doesn't produce. CPU and memory usage are in Perf.
- **Perf**: CPU and memory usage, requests and limits of the nodes and containers.
- **KubeServices**: Tracks the inventory of Kubernetes services (ClusterIP, NodePort, LoadBalancer).
- **KubeNodeInventory**: The nodes as Kubernetes sees them: status, labels and Kubernetes version.
- **KubePVInventory**: Persistent volumes and their claims.
- **KubeMonAgentEvents**: Diagnostic events related to the monitoring agent itself. Empty on the emulator, which runs no agent.

Every activity operation writes one line in the form `Activity <operation>: <details>`, where the operation is `added`, `updated`, `deleted` or `retrieved`:

```text
Activity added: Go to Viareggio
Activity updated: Go to Lucca (id 6f1c2a…)
Activity deleted: 6f1c2a…
Activity retrieved: 4 activities
```

ContainerLogV2 infers each line's `LogLevel` from its text, so these lines are stored at the `info` level, and a line that names no level is stored as `unknown`.

Kubernetes events by kind and reason:

```kusto
KubeEvents
| summarize EventCount = count() by ObjectKind, Reason
| sort by EventCount desc
```

Kubernetes events per minute by reason:

```kusto
KubeEvents
| summarize EventCount = count() by bin(TimeGenerated, 1m), Reason
| render timechart with (title="Kubernetes events by reason")
```

Pods and containers over time:

```kusto
union
    (KubePodInventory
    | summarize Count = dcount(PodUid) by bin(TimeGenerated, 1m)
    | extend Series = "Pods"),
    (ContainerInventory
    | summarize Count = dcount(ContainerID) by bin(TimeGenerated, 1m)
    | extend Series = "Containers")
| render timechart with (title="Pod vs. Container Count in the AKS Cluster")
```

Nodes over time:

```kusto
ContainerNodeInventory
| summarize NodeCount = dcount(Computer) by bin(TimeGenerated, 1m)
| render timechart with (title="Node Count in the AKS Cluster")
```

Log lines by container and level in the last two hours:

```kusto
ContainerLogV2
| where TimeGenerated > ago(2h)
| where PodNamespace != "kube-system"
| extend Level = toupper(LogLevel)
| summarize Count = count() by ContainerName, Level
| render barchart with (kind=stacked, title="Log Output by Container and Level")
```

Activities added, with the pod that served each request:

```kusto
ContainerLogV2
| where LogMessage contains "Activity added"
| project TimeGenerated, PodName, LogMessage
```

Activity operations:

```kusto
ContainerLogV2
| where LogMessage has_any ("added", "updated", "deleted", "retrieved")
| parse tostring(LogMessage) with * "Activity " Operation ": " Details
| where Operation in ("added", "updated", "deleted", "retrieved")
| project TimeGenerated, PodName, Operation, Details
```

Activity operations per minute by type:

```kusto
ContainerLogV2
| where LogMessage has_any ("added", "updated", "deleted", "retrieved")
| parse tostring(LogMessage) with * "Activity " Operation ": " *
| where Operation in ("added", "updated", "deleted", "retrieved")
| summarize Count = count() by bin(TimeGenerated, 1m), Operation
| render columnchart with (kind=stacked, title="Operations by type")
```
