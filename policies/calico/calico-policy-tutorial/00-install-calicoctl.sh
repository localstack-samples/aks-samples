#!/bin/bash

# For more information, see:
# https://docs.tigera.io/calico/latest/operations/calicoctl/install
# https://docs.tigera.io/calico/latest/network-policy/get-started/calico-policy/calico-policy-tutorial

# calicoctl is the command line interface used to manage Calico resources such as
# GlobalNetworkPolicy and the projectcalico.org/v3 NetworkPolicy used in this tutorial.

# Variables
CALICOCTL_VERSION=$(curl -s https://api.github.com/repos/projectcalico/calico/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
CLI_ARCH=amd64

# Detect the CPU architecture so the correct calicoctl binary is downloaded
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi

# Download the calicoctl binary for the latest release and the detected architecture
curl -L --fail --remote-name https://github.com/projectcalico/calico/releases/download/${CALICOCTL_VERSION}/calicoctl-linux-${CLI_ARCH}

# Make the binary executable and move it onto the PATH
chmod +x calicoctl-linux-${CLI_ARCH}
sudo mv calicoctl-linux-${CLI_ARCH} /usr/local/bin/calicoctl

# Verify the installation
calicoctl version
