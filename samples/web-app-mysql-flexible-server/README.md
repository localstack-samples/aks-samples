# Vacation Planner: Azure Database for MySQL flexible server

This sample demonstrates a Python Flask single-page web application called *Vacation Planner* hosted on an [Azure Kubernetes Service (AKS)](https://learn.microsoft.com/en-us/azure/aks/what-is-aks) cluster in the cloud on Azure or locally in the LocalStack emulator for Azure. The app runs in a dedicated namespace and stores activity data in the `activities` table of the `plannerdb` database on an [Azure Database for MySQL flexible server](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/overview).

The application connects to MySQL using a dedicated application user (rather than the server admin) over TLS, and the deployment scripts seed the `activities` table with a handful of sample plans so the app shows data on first load.

Before installing the sample, make sure to create an [Azure Kubernetes Service (AKS)](https://learn.microsoft.com/en-us/azure/aks/what-is-aks) cluster by using one of the following scripts:

- [scripts/01-system-assigned-managed-identity.sh](../../scripts/01-system-assigned-managed-identity.sh): creates the cluster using a system-assigned managed identity as its cluster identity.
- [scripts/01-user-assigned-managed-identity.sh](../../scripts/01-user-assigned-managed-identity.sh): creates the cluster using a user-assigned managed identity as its cluster identity.

The `01-deploy-resources.sh` script needs the `mysql` client installed on the host (for example `sudo apt install -y mysql-client`) to bootstrap the application user, schema, and seed data.

All commands below are run from this sample's `scripts/` folder.

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
| [`00-variables.sh`](scripts/00-variables.sh) | Defines the variables shared across the other scripts (resource names, image tag, MySQL credentials, Kubernetes namespace, …). The other scripts load these values by sourcing this file. |
| [`01-deploy-resources.sh`](scripts/01-deploy-resources.sh) | Deploys the Azure resources used by this sample: the resource group, the [Azure Container Registry (ACR)](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-intro), the [Azure Database for MySQL flexible server](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/overview) and the `plannerdb` database, a permissive firewall rule (dev/test only), a dedicated application user, and the `activities` table, which it also seeds with sample data. Requires the `mysql` client on the host. |
| [`02-build-docker-image.sh`](scripts/02-build-docker-image.sh) | Builds the Docker image for the web app from the [`src/`](src/) folder. |
| [`03-run-docker-container.sh`](scripts/03-run-docker-container.sh) | Runs the web app in a local Docker container (no Kubernetes) to validate that it starts and connects to the database as expected. |
| [`04-push-docker-image.sh`](scripts/04-push-docker-image.sh) | Tags and pushes the Docker image to the Azure Container Registry, on Azure or in the LocalStack emulator. |
| [`05-deploy-app.sh`](scripts/05-deploy-app.sh) | Uses the YAML manifests below (templated with `yq`) to deploy the app to the AKS cluster. |
| [`Dockerfile`](scripts/Dockerfile) | Builds the Docker image of the web app. |
| [`namespace.yml`](scripts/namespace.yml) | Creates the Kubernetes namespace. |
| [`configmap.yml`](scripts/configmap.yml) | Creates the ConfigMap holding non-secret input values (MySQL host, port, database, user, TLS flag, login name) passed to the app as environment variables. |
| [`secret.yml`](scripts/secret.yml) | Creates the Secret holding sensitive values (the MySQL password and the Flask secret key) passed to the app as environment variables. |
| [`deployment.yml`](scripts/deployment.yml) | Creates the Kubernetes Deployment, including the pod specification for the web app. |
| [`service.yml`](scripts/service.yml) | Creates the `ClusterIP` Service that exposes the web app inside the cluster. |

## Accessing the web app

The app is exposed through a `ClusterIP` service, which is only reachable from inside the cluster. Port-forward it to a local port to open it from your machine:

```bash
kubectl port-forward service/vacation-planner-mysql 8080:80 -n vacation-planner-mysql
```

Then browse to [http://localhost:8080](http://localhost:8080). Alternatively, use a tool such as [k9s](https://k9scli.io/) to start the port-forward interactively.
