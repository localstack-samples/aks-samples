# Security Policy

## Scope

This repository contains **sample code**: end-to-end demonstrations of how to deploy an [Azure Kubernetes Service (AKS)](https://learn.microsoft.com/en-us/azure/aks/what-is-aks) cluster and run a workload on it, against Azure or against the [LocalStack for Azure](https://docs.localstack.cloud/azure/) emulator. It is written to be read and adapted, not to be deployed as-is into production.

Two consequences worth stating plainly:

- **The credentials in these samples are throwaway demo values.** Database passwords, admin logins and Flask secret keys are hardcoded so a sample runs with a single command. They protect resources you create in your own subscription for the duration of a demo. Change them before you keep anything around, and never reuse them.
- **Security trade-offs are chosen for clarity.** Public network access, permissive mount options and secrets passed through environment variables all make a sample easier to follow and are called out in the sample's README where they matter. Harden them for real workloads.

## Reporting a vulnerability

If you find a vulnerability in this repository, for example a real credential committed by mistake, a script that exfiltrates data, or a dependency with a known exploit, report it privately through GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability): open the **Security** tab of this repository and choose **Report a vulnerability**.

Please do not open a public issue for something exploitable.

For a vulnerability in LocalStack itself rather than in these samples, see the [LocalStack documentation](https://docs.localstack.cloud/) for the current support channels.
