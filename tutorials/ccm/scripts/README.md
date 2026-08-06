## Cloud Controller Manager (CCM) Load Balancer Samples

The [Azure cloud controller manager](https://cloud-provider-azure.sigs.k8s.io/) (`cloud-provider-azure`) is the AKS component that turns Kubernetes `Service` and `Node` events into Azure API calls. When you create a `Service` of type `LoadBalancer`, the CCM provisions an Azure load balancer frontend, a public IP, and network security group rules, then writes the assigned address back as the Service `EXTERNAL-IP`.

The CCM is a **control-plane, provisioning-time** component: it reconciles the Azure resources when a Service is created, updated, or deleted. It is **not** in the runtime data path (traffic flows through the load balancer and kube-proxy to the pods, not through the CCM).

These scripts exercise that reconcile against the [LocalStack for Azure](https://docs.localstack.cloud/azure/) emulator: public and internal load balancers, source-range NSG rules, the nodeIP backend-pool variant, and an NGINX ingress controller.

Because the emulated load balancer has no real dataplane, the `EXTERNAL-IP` is a synthetic, non-routable placeholder. To actually reach a workload, use `kubectl port-forward`, which tunnels straight to the pod and bypasses the `EXTERNAL-IP`.

> **Running on LocalStack?** Install the [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/) and run `lstk az start-interception` to route Azure CLI calls to the emulator. See [Run against LocalStack](../../../README.md#run-against-localstack) for the full setup.

## Prerequisites

- An AKS cluster reachable through `kubectl`, created by [scripts/01-user-assigned-managed-identity.sh](../../../scripts/01-user-assigned-managed-identity.sh). The scripts do not create the cluster; they source `./00-variables.sh`, whose values must match it (`local-aks-test` in resource group `local-rg`, location `ItalyNorth`).
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/) (`az`) and [kubectl](https://kubernetes.io/docs/tasks/tools/).
- [Helm](https://helm.sh/) for `05-test-nginx-ingress-controller.sh`.

## How to run

Each script sources `./00-variables.sh`, merges the cluster credentials, and guards on the node resource group (exiting with instructions if the cluster does not exist). Run them from this folder, in order or individually.

```bash
cd ccm/scripts
./01-test-public-loadbalancer.sh
./02-test-internal-loadbalancer.sh
./03-test-loadbalancer-source-ranges.sh
./05-test-nginx-ingress-controller.sh
```

## Scripts

- `00-variables.sh`: Shared variables sourced by every test: cluster name, resource group, and location (which must match the cluster-creation script); the derived node resource group; the load-balancer, namespace, Service, ingress, and backend names; and the `EXTERNAL-IP` poll timeout.
- `01-test-public-loadbalancer.sh`: Creates a public `Service` of type `LoadBalancer` and asserts it receives an `EXTERNAL-IP`, that a matching public IP exists in the node resource group, and that the `kubernetes` load balancer has a frontend and a rule.
- `02-test-internal-loadbalancer.sh`: Creates an internal LoadBalancer Service (via the `service.beta.kubernetes.io/azure-load-balancer-internal` annotation) and asserts it receives a private `EXTERNAL-IP` on the `kubernetes-internal` load balancer and that no public IP is created for it.
- `03-test-loadbalancer-source-ranges.sh`: Creates a public Service with `loadBalancerSourceRanges` and asserts the CCM reconciles an inbound Allow rule scoped to that CIDR on the node resource group network security group.
- `04-test-nodeip-backend-pool.sh`: Exercises the `nodeIP` backend-pool variant. It self-guards on the cluster's `backendPoolType`: unless the cluster was created with `--load-balancer-backend-pool-type nodeIP` it prints how to re-create the cluster and exits, because `backendPoolType` is a create-time property. When it is `nodeIP`, it asserts the `kubernetes` backend pool holds node IP addresses rather than NIC IP-configuration references.
- `05-test-nginx-ingress-controller.sh`: Installs the NGINX ingress controller (its own front Service is type `LoadBalancer`, so the CCM assigns it an `EXTERNAL-IP` and a node resource group public IP), then deploys a backend Deployment, a ClusterIP Service, and an Ingress, and verifies that traffic reaches the backend through the controller with a `kubectl port-forward` pass-through check.

## Resources

- [Cloud Controller Manager (Kubernetes documentation)](https://kubernetes.io/docs/concepts/architecture/cloud-controller/)
- [Cluster Architecture (Kubernetes documentation)](https://kubernetes.io/docs/concepts/architecture/)
- [Developing Cloud Controller Manager (Kubernetes)](https://kubernetes.io/docs/tasks/administer-cluster/developing-cloud-controller-manager/)
- [Cloud Controller Manager Administration (Kubernetes)](https://kubernetes.io/docs/tasks/administer-cluster/running-cloud-controller/)
- [KEP-2392: Cloud Controller Manager](https://github.com/kubernetes/enhancements/tree/master/keps/sig-cloud-provider/2392-cloud-controller-manager)
- [Cloud provider for Azure documentation site](https://cloud-provider-azure.sigs.k8s.io/)
- [Core concepts for Azure Kubernetes Service (AKS)](https://learn.microsoft.com/azure/aks/core-aks-concepts)
- [Use a public standard load balancer in AKS](https://learn.microsoft.com/azure/aks/load-balancer-standard)
- [Use an internal load balancer in AKS](https://learn.microsoft.com/azure/aks/internal-lb)
- [Use a static public IP address and DNS label with the AKS load balancer](https://learn.microsoft.com/azure/aks/static-ip)
- [Configure the public standard load balancer in AKS](https://learn.microsoft.com/azure/aks/configure-load-balancer-standard)
- [Managed NGINX ingress with the application routing add-on](https://learn.microsoft.com/azure/aks/app-routing)
