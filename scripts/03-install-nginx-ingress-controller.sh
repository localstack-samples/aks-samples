#!/bin/bash

# Variables
nginxNamespace="ingress-basic"
nginxRepoName="ingress-nginx"
nginxRepoUrl="https://kubernetes.github.io/ingress-nginx"
nginxChartName="ingress-nginx"
nginxReleaseName="nginx-ingress"
nginxReplicaCount=3

# Use Helm to deploy an NGINX ingress controller
result=$(helm list -n $nginxNamespace | grep $nginxReleaseName | awk '{print $1}')

if [[ -n $result ]]; then
  echo "[$nginxReleaseName] ingress controller already exists in the [$nginxNamespace] namespace"
else
  # Check if the ingress-nginx repository is not already added
  result=$(helm repo list | grep $nginxRepoName | awk '{print $1}')

  if [[ -n $result ]]; then
    echo "[$nginxRepoName] Helm repo already exists"
  else
    # Add the ingress-nginx repository
    echo "Adding [$nginxRepoName] Helm repo..."
    helm repo add $nginxRepoName $nginxRepoUrl
  fi

  # Update your local Helm chart repository cache
  echo 'Updating Helm repos...'
  helm repo update

  # Deploy NGINX ingress controller
  echo "Deploying [$nginxReleaseName] NGINX ingress controller to the [$nginxNamespace] namespace..."
  helm install $nginxReleaseName $nginxRepoName/$nginxChartName \
    --create-namespace \
    --namespace $nginxNamespace \
    --set controller.metrics.enabled=true \
    --set controller.metrics.serviceMonitor.enabled=true \
    --set controller.metrics.serviceMonitor.additionalLabels.release="prometheus" \
    --set controller.replicaCount=$nginxReplicaCount \
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz
fi

# Get values
helm get values $nginxReleaseName --namespace $nginxNamespace