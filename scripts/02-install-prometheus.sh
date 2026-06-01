#!/bin/bash

# Variables
namespace="prometheus"
release="prometheus"

# Add Helm repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

# Update Helm repos
helm repo update

# Install Prometheus
helm install $release prometheus-community/kube-prometheus-stack \
  --create-namespace \
  --namespace $namespace \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

# Get values
helm get values $release --namespace $namespace
