## Kubernetes Gateway API on AKS with NGINX Gateway Fabric

The [Kubernetes Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/) is a specification for traffic management on Kubernetes clusters. It improves on the [Ingress API](https://kubernetes.io/docs/concepts/services-networking/ingress/) with a role-oriented, provider-agnostic model for advanced routing, expressed through resources such as `GatewayClass`, `Gateway`, and `HTTPRoute`.

On AKS the [Managed Gateway API installation](https://learn.microsoft.com/en-us/azure/aks/managed-gateway-api) installs and manages the standard-channel Gateway API [Custom Resource Definitions (CRDs)](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/) on the cluster. It installs the CRDs only: it does not install any implementation and does not create a `GatewayClass`. An implementation that actually routes traffic must be deployed separately, exactly as on real AKS.

This tutorial enables the Managed Gateway API on an AKS cluster (or the [LocalStack for Azure](https://docs.localstack.cloud/azure/) emulator), installs [NGINX Gateway Fabric](https://docs.nginx.com/nginx-gateway-fabric/) as the Gateway API implementation, and exposes an [echo-server](https://github.com/Ealenn/Echo-Server) backend through a `Gateway` and an `HTTPRoute`. It then verifies, from the host, that a request for the route's hostname reaches the backend while a request for any other hostname does not, proving the gateway makes the routing decision. There is no cert-manager and no DNS: the hostname is local-only and reached with `kubectl port-forward` and an explicit `Host` header.

## Prerequisites

- An AKS cluster reachable through `kubectl`, created with [scripts/01-user-assigned-managed-identity.sh](../../scripts/01-user-assigned-managed-identity.sh) (or the system-assigned variant). The values in [00-variables.sh](00-variables.sh) (cluster `local-aks-test`, resource group `local-rg`, location `ItalyNorth`) must match the cluster the script creates; edit them if you changed the cluster script's `prefix`, `suffix`, or `location`.
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`) version `2.86.0` or later, which is required for the `--enable-gateway-api` flag.
- [kubectl](https://kubernetes.io/docs/tasks/tools/) configured for the cluster.
- [Helm](https://helm.sh/) to install NGINX Gateway Fabric.
- `curl` and [jq](https://jqlang.github.io/jq/) for the routing check. `04-test-routing.sh` installs `jq` with `apt` if it is missing on a Debian or Ubuntu host.

The cluster-creation scripts already enable the Managed Gateway API at create time, so `01-enable-gateway-api.sh` is idempotent: on such a cluster it detects the installation and leaves it in place. It still runs cleanly on a cluster created without it, enabling it through the live `az aks update` path.

## How it works

Run the numbered scripts in order. Each one sources [00-variables.sh](00-variables.sh) and is idempotent, so it can be re-run safely.

| Script | What it does | Expected result |
| --- | --- | --- |
| `00-variables.sh` | Shared variables (cluster name and resource group, the `gateway.networking.k8s.io` CRD group, the NGINX Gateway Fabric release, and the echo-server names, hostname, and port). Sourced by every script, never run directly. | Variables exported. |
| `01-enable-gateway-api.sh` | Enables the Managed Gateway API on the cluster (`az aks update --enable-gateway-api`), merges the cluster credentials into `kubeconfig`, and waits for the CRDs. | The standard-channel CRDs (`gatewayclasses`, `gateways`, `grpcroutes`, `httproutes`, `referencegrants`) are installed; the bundle version and `standard` channel are printed. |
| `02-install-nginx-gateway-fabric.sh` | Installs NGINX Gateway Fabric via Helm from its OCI registry, with its front `Service` of type `LoadBalancer`. | The `nginx` `GatewayClass` registered by the chart reaches `Accepted`. |
| `03-deploy-echoserver.sh` | Deploys the `echoserver` `Deployment` and `ClusterIP` `Service`, a `Gateway` on the `nginx` class with an HTTP listener for `echo.local`, and an `HTTPRoute` binding `echo.local` to the Service. | The `Gateway` reaches `Programmed` and the `Deployment` reaches `Available`. |
| `04-test-routing.sh` | Waits for the NGINX Gateway Fabric data-plane pods, port-forwards the per-`Gateway` `Service`, then `curl`s it with the claimed `Host` header and with an unclaimed one. | `echo.local` returns HTTP `200`; the unclaimed host does not; the echo-server response is printed. |
| `05-cleanup.sh` | Deletes the sample namespace and uninstalls NGINX Gateway Fabric. Pass `--disable-gateway-api` to also remove the Managed Gateway API CRDs. | The sample resources are removed. |

```bash
cd gateway-api/scripts
./01-enable-gateway-api.sh
./02-install-nginx-gateway-fabric.sh
./03-deploy-echoserver.sh
./04-test-routing.sh
# ./05-cleanup.sh                       # when finished
# ./05-cleanup.sh --disable-gateway-api # also remove the Gateway API CRDs
```

## Scripts

- `00-variables.sh`: Defines the shared variables sourced by every other script: the target cluster (`local-aks-test`) and resource group (`local-rg`), the `gateway.networking.k8s.io` CRD group, the NGINX Gateway Fabric namespace, release name, OCI chart, and `nginx` `GatewayClass`, and the echo-server namespace, workload names, `echo.local` hostname, container image, and port.
- `01-enable-gateway-api.sh`: Confirms the cluster exists, enables the Managed Gateway API with `az aks update --enable-gateway-api` (skipping the update when `ingressProfile.gatewayApi.installation` is already `Standard`), merges the cluster credentials into `kubeconfig`, and polls until the standard-channel CRDs appear. It then lists the CRDs and the Gateway API resources (`kubectl api-resources`) and prints the `gateway.networking.k8s.io/bundle-version` and `gateway.networking.k8s.io/channel` annotations the managed installation stamps on them.
- `02-install-nginx-gateway-fabric.sh`: Verifies the CRDs are present, then `helm install`s NGINX Gateway Fabric from `oci://ghcr.io/nginx/charts/nginx-gateway-fabric` (unpinned, latest) with `nginx.service.type=LoadBalancer`, and waits for the `nginx` `GatewayClass` to be `Accepted`. The Managed Gateway API installs only the CRDs, so this bring-your-own implementation is what actually serves traffic.
- `03-deploy-echoserver.sh`: Verifies the `nginx` `GatewayClass` exists, creates the `gateway-api-test` namespace, and applies the echo-server `Deployment` and `ClusterIP` `Service`, a `Gateway` on the `nginx` class with an HTTP listener for `echo.local`, and an `HTTPRoute` that routes every path of `echo.local` to the Service. It waits for the `Gateway` to be `Programmed` and the `Deployment` to be `Available`.
- `04-test-routing.sh`: Discovers the per-`Gateway` data-plane `Service` NGINX Gateway Fabric provisions (by the `gateway.networking.k8s.io/gateway-name` label), waits for its pods to be `Ready`, and `kubectl port-forward`s it to a local port. It asserts that a request with `Host: echo.local` returns HTTP `200` and that a request for an unclaimed host does not reach the backend, then prints a full echo-server response. The `LoadBalancer` external IP is synthetic on the emulator, so the data path is exercised through the port-forward.
- `05-cleanup.sh`: Deletes the `gateway-api-test` namespace (removing the `Deployment`, `Service`, `Gateway`, and `HTTPRoute`) and uninstalls the NGINX Gateway Fabric release and its namespace. When passed `--disable-gateway-api`, it also runs `az aks update --disable-gateway-api`, which removes the managed CRDs and, with them, any remaining Gateway API resources.

The Kubernetes manifests (the `Deployment`, `Service`, `Gateway`, and `HTTPRoute`) are defined inline in `03-deploy-echoserver.sh` and templated from the variables in `00-variables.sh`, so there are no separate YAML files.

## Resources

- [Gateway API (Kubernetes documentation)](https://kubernetes.io/docs/concepts/services-networking/gateway/)
- [Install Managed Gateway API CRDs on Azure Kubernetes Service (AKS)](https://learn.microsoft.com/en-us/azure/aks/managed-gateway-api)
- [Gateway API project](https://gateway-api.sigs.k8s.io/)
- [kubernetes-sigs/gateway-api releases](https://github.com/kubernetes-sigs/gateway-api/releases)
- [NGINX Gateway Fabric](https://docs.nginx.com/nginx-gateway-fabric/)
- [Ingress API (Kubernetes documentation)](https://kubernetes.io/docs/concepts/services-networking/ingress/)
