#/bin/bash

# For more information, see:
# https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver
# https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-identity-access

# Variables
source ./00-variables.sh

# Create the pod
echo "Creating the [$POD_NAME] pod in the [$NAMESPACE] namespace..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
kind: Pod
apiVersion: v1
metadata:
  name: $POD_NAME
spec:
  containers:
    - name: nginx
      image: nginx
      resources:
        requests:
          memory: "32Mi"
          cpu: "50m"
        limits:
          memory: "64Mi"
          cpu: "100m"
      volumeMounts:
        - name: secrets-store
          mountPath: "/mnt/secrets"
          readOnly: true
  volumes:
    - name: secrets-store
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "$SECRET_PROVIDER_CLASS_NAME"
EOF