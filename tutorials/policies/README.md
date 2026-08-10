## Kubernetes Network Policy Tutorials

[Kubernetes network policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) control which pods may talk to each other and to the outside world. On AKS the rules are enforced by a policy engine tied to the cluster's data plane, so the engine is chosen when the cluster is created: [scripts/01-user-assigned-managed-identity.sh](../../scripts/01-user-assigned-managed-identity.sh) offers Azure, Cilium, and Calico network policy in its menu ([AKS network policies](https://learn.microsoft.com/en-us/azure/aks/use-network-policies)).

These tutorials each build a policy scenario step by step and verify, from inside probe pods, that allowed traffic flows and everything else is blocked.

| Tutorial | Engine | Demonstrates |
| --- | --- | --- |
| [calico/calico-policy-tutorial](calico/calico-policy-tutorial) | Calico | A cluster-wide default-deny `GlobalNetworkPolicy`, then namespaced `NetworkPolicy` rules that selectively re-open egress and ingress (zero trust). |
| [cilium/egress-tutorial](cilium/egress-tutorial) | Cilium | DNS-aware (FQDN) egress control: an exact hostname, a wildcard pattern, and a pattern locked to a single port. |
| [cilium/ingress-tutorial](cilium/ingress-tutorial) | Cilium | Identity-aware ingress, first at L3/L4 (which workloads may connect) and then at L7 (which HTTP calls they may make). |

> **Running on LocalStack?** Install the [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/) and run `lstk az start-interception` to route Azure CLI calls to the emulator. See [Run against LocalStack](../../README.md#run-against-localstack) for the full setup.

## Architecture

The engine is chosen when the cluster is created and cannot be swapped afterwards, so each tutorial only runs on a cluster built for its engine:

```mermaid
%%{init: {'themeVariables': {'clusterBkg': 'transparent', 'clusterBorder': '#8c8c8c'}}}%%
flowchart LR
    create(["scripts/01-user-assigned-managed-identity.sh<br/>picks --network-policy and --network-dataplane"])

    subgraph aks["Azure Kubernetes Service cluster, one engine per cluster"]
        azure["--network-policy azure<br/>azure data plane<br/>no tutorial in this folder"]
        calico["--network-policy calico<br/>azure data plane<br/>calico-system, calico-apiserver"]
        cilium["--network-policy cilium<br/>cilium data plane<br/>cilium-agent in kube-system"]
    end

    k8spol["networking.k8s.io/v1<br/>NetworkPolicy, applied with kubectl"]
    calicopol["projectcalico.org/v3<br/>GlobalNetworkPolicy and NetworkPolicy,<br/>applied with calicoctl"]
    ciliumpol["cilium.io/v2<br/>CiliumNetworkPolicy, applied with kubectl"]

    subgraph tutorials["Tutorials"]
        calicotut["calico/calico-policy-tutorial<br/>namespace advanced-policy-demo<br/>cluster-wide default-deny, then selective allow"]
        egresstut["cilium/egress-tutorial<br/>namespace starwars<br/>FQDN egress: name, pattern, pattern plus port"]
        ingresstut["cilium/ingress-tutorial<br/>namespace starwars<br/>identity-aware ingress at L3/L4, then L7 HTTP"]
    end

    create -->|"chosen at cluster creation"| azure
    create --> calico
    create --> cilium
    k8spol -.->|"enforced by every engine"| azure
    k8spol -.-> calico
    k8spol -.-> cilium
    calicopol -.->|"enforced by"| calico
    ciliumpol -.->|"enforced by"| cilium
    calico -->|"required by"| calicotut
    cilium -->|"required by"| egresstut
    cilium -->|"required by"| ingresstut
```

## Prerequisites

- An AKS cluster reachable through `kubectl`, created with the policy engine that matches the tutorial you want to run (Calico for the Calico tutorial, Cilium for the two Cilium tutorials).
- [kubectl](https://kubernetes.io/docs/tasks/tools/) configured for the cluster.
- The engine's CLI, installed by each tutorial's `00-*.sh` script (`calicoctl` for Calico; `cilium` and `hubble` for Cilium).

Follow the README in each tutorial folder for the full walkthrough.

## Resources

- [Network Policies (Kubernetes documentation)](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Secure traffic between pods using network policies in AKS](https://learn.microsoft.com/en-us/azure/aks/use-network-policies)
- [Project Calico documentation](https://docs.tigera.io/calico/latest/about/)
- [Cilium documentation](https://docs.cilium.io/)
