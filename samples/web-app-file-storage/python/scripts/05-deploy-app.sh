#!/bin/bash

# Variables
source ./00-variables.sh

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# The combination to deploy is the one chosen in 01-deploy-resources.sh, which persisted it to
# .deploy-options.env, or the one exported in the environment. It is never guessed here: deploying a
# static volume for a file share that was never created, or an NFS volume against an SMB share, leaves
# the pods stuck in ContainerCreating with a mount error.
if [[ -z "$PROVISIONING_MODE" || -z "$FILE_SHARE_PROTOCOL" ]]; then
	echo "The provisioning mode and the file share protocol are not set."
	echo "Run ./01-deploy-resources.sh first, or export PROVISIONING_MODE (static|dynamic) and FILE_SHARE_PROTOCOL (smb|nfs)."
	exit 1
fi

if [[ "$PROVISIONING_MODE" != 'static' && "$PROVISIONING_MODE" != 'dynamic' ]]; then
	echo "Invalid provisioning mode [$PROVISIONING_MODE]: expected [static] or [dynamic]"
	exit 1
fi

if [[ "$FILE_SHARE_PROTOCOL" != 'smb' && "$FILE_SHARE_PROTOCOL" != 'nfs' ]]; then
	echo "Invalid file share protocol [$FILE_SHARE_PROTOCOL]: expected [smb] or [nfs]"
	exit 1
fi

echo "Deploying the app with [$PROVISIONING_MODE] provisioning over [${FILE_SHARE_PROTOCOL^^}]..."

# Pick the storage account that holds the file share for the selected protocol
if [[ "$FILE_SHARE_PROTOCOL" == 'nfs' ]]; then
	STORAGE_ACCOUNT_NAME="$NFS_STORAGE_ACCOUNT_NAME"
else
	STORAGE_ACCOUNT_NAME="$SMB_STORAGE_ACCOUNT_NAME"
fi

# Generate a stable Flask SECRET_KEY (sessions survive pod restarts)
SECRET_KEY=$(openssl rand -hex 32)

# Get the login server for the Azure Container Registry
echo "Getting login server for Azure Container Registry [$ACR_NAME]..."
ACR_LOGIN_SERVER=$(az acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "loginServer" \
	--output tsv \
	--only-show-errors)

if [ -n "$ACR_LOGIN_SERVER" ]; then
	echo "Login server retrieved successfully: $ACR_LOGIN_SERVER"
else
	echo "Failed to retrieve login server for Azure Container Registry [$ACR_NAME]."
	exit 1
fi

FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

# Create namespace
cat namespace.yml |
yq "(.metadata.name)|="\""$NAMESPACE"\" |
kubectl apply -f -

# Create secret with the Flask secret key. Unlike the sibling samples, no storage credential is
# passed to the app: it reads and writes files on the mounted share and never authenticates to Azure.
cat secret.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.metadata.name)|="\""$SECRET_NAME"\" |
yq "(.data.SECRET_KEY)|="\""$(echo -n $SECRET_KEY | base64 -w0)"\" |
kubectl apply -f -

# Create configmap with environment variables
cat configmap.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.metadata.name)|="\""$CONFIGMAP_NAME"\" |
yq "(.data.ACTIVITIES_DIR)|="\""$ACTIVITIES_DIR"\" |
kubectl apply -f -

# Create the configmap holding the sample activities used to seed the file share
cat seed-configmap.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.metadata.name)|="\""$SEED_CONFIGMAP_NAME"\" |
kubectl apply -f -

if [[ "$PROVISIONING_MODE" == 'static' ]]; then
	# Static provisioning: bind the claim to a volume that points at the file share created by
	# 01-deploy-resources.sh.
	if [[ "$FILE_SHARE_PROTOCOL" == 'smb' ]]; then
		# The driver mounts an SMB share with the storage account key, so it needs the key in a secret
		echo "Retrieving the key of the [$STORAGE_ACCOUNT_NAME] storage account..."
		STORAGE_ACCOUNT_KEY=$(az storage account keys list \
			--account-name $STORAGE_ACCOUNT_NAME \
			--resource-group $RESOURCE_GROUP_NAME \
			--query "[0].value" \
			--output tsv \
			--only-show-errors)

		if [ -z "$STORAGE_ACCOUNT_KEY" ]; then
			echo "Failed to retrieve the key of the [$STORAGE_ACCOUNT_NAME] storage account."
			exit 1
		fi

		cat storage-secret.yml |
		yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
		yq "(.metadata.name)|="\""$STORAGE_SECRET_NAME"\" |
		yq "(.data.azurestorageaccountname)|="\""$(echo -n $STORAGE_ACCOUNT_NAME | base64 -w0)"\" |
		yq "(.data.azurestorageaccountkey)|="\""$(echo -n $STORAGE_ACCOUNT_KEY | base64 -w0)"\" |
		kubectl apply -f -

		# The SMB and NFS volumes are applied by two separate pipelines on purpose: yq's |= operator
		# creates a missing path, so setting nodeStageSecretRef.namespace on the NFS volume would add a
		# secret reference to a volume that must not have one.
		cat persistentvolume-smb.yml |
		yq "(.metadata.name)|="\""$PERSISTENT_VOLUME_NAME"\" |
		yq "(.spec.csi.volumeHandle)|="\""${RESOURCE_GROUP_NAME}#${STORAGE_ACCOUNT_NAME}#${FILE_SHARE_NAME}"\" |
		yq "(.spec.csi.volumeAttributes.resourceGroup)|="\""$RESOURCE_GROUP_NAME"\" |
		yq "(.spec.csi.volumeAttributes.storageAccount)|="\""$STORAGE_ACCOUNT_NAME"\" |
		yq "(.spec.csi.volumeAttributes.shareName)|="\""$FILE_SHARE_NAME"\" |
		yq "(.spec.csi.nodeStageSecretRef.name)|="\""$STORAGE_SECRET_NAME"\" |
		yq "(.spec.csi.nodeStageSecretRef.namespace)|="\""$NAMESPACE"\" |
		kubectl apply -f -
	else
		cat persistentvolume-nfs.yml |
		yq "(.metadata.name)|="\""$PERSISTENT_VOLUME_NAME"\" |
		yq "(.spec.csi.volumeHandle)|="\""${RESOURCE_GROUP_NAME}#${STORAGE_ACCOUNT_NAME}#${FILE_SHARE_NAME}"\" |
		yq "(.spec.csi.volumeAttributes.resourceGroup)|="\""$RESOURCE_GROUP_NAME"\" |
		yq "(.spec.csi.volumeAttributes.storageAccount)|="\""$STORAGE_ACCOUNT_NAME"\" |
		yq "(.spec.csi.volumeAttributes.shareName)|="\""$FILE_SHARE_NAME"\" |
		kubectl apply -f -
	fi

	# The claim is committed in its static shape, so it is applied as it is
	cat persistentvolumeclaim.yml |
	yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
	yq "(.metadata.name)|="\""$PERSISTENT_VOLUME_CLAIM_NAME"\" |
	yq "(.spec.volumeName)|="\""$PERSISTENT_VOLUME_NAME"\" |
	kubectl apply -f -
else
	# Dynamic provisioning: the CSI driver creates the storage account and the file share when the
	# claim is bound, so there is no volume to create, only a storage class to select.
	if [[ "$FILE_SHARE_PROTOCOL" == 'nfs' ]]; then
		# None of the built-in azurefile* classes provisions an NFS share
		cat storageclass-nfs.yml |
		yq "(.metadata.name)|="\""$NFS_STORAGE_CLASS_NAME"\" |
		kubectl apply -f -

		STORAGE_CLASS_NAME="$NFS_STORAGE_CLASS_NAME"
	else
		STORAGE_CLASS_NAME="$SMB_STORAGE_CLASS_NAME"

		echo "Checking if the [$STORAGE_CLASS_NAME] storage class exists in the cluster..."
		kubectl get storageclass "$STORAGE_CLASS_NAME" &>/dev/null

		if [[ $? != 0 ]]; then
			echo "No [$STORAGE_CLASS_NAME] storage class exists in the cluster."
			echo "It is installed with the Azure Files CSI driver: check that the driver is enabled with"
			echo "  az aks show --name $AKS_CLUSTER_NAME --resource-group $RESOURCE_GROUP_NAME --query storageProfile.fileCsiDriver"
			exit 1
		fi
	fi

	# Drop the static binding and let the storage class provision the volume
	cat persistentvolumeclaim.yml |
	yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
	yq "(.metadata.name)|="\""$PERSISTENT_VOLUME_CLAIM_NAME"\" |
	yq "del(.spec.volumeName)" |
	yq "(.spec.storageClassName)|="\""$STORAGE_CLASS_NAME"\" |
	kubectl apply -f -
fi

# Create deployment
cat deployment.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.metadata.name)|="\""$DEPLOYMENT_NAME"\" |
yq "(.spec.template.spec.volumes[0].persistentVolumeClaim.claimName)|="\""$PERSISTENT_VOLUME_CLAIM_NAME"\" |
yq "(.spec.template.spec.volumes[1].configMap.name)|="\""$SEED_CONFIGMAP_NAME"\" |
yq "(.spec.template.spec.initContainers[0].image)|="\""$FULL_IMAGE"\" |
yq "(.spec.template.spec.initContainers[0].imagePullPolicy)|="\""$IMAGE_PULL_POLICY"\" |
yq "(.spec.template.spec.initContainers[0].env[0].value)|="\""$FILE_SHARE_PROTOCOL"\" |
yq "(.spec.template.spec.initContainers[0].env[1].valueFrom.configMapKeyRef.name)|="\""$CONFIGMAP_NAME"\" |
yq "(.spec.template.spec.initContainers[0].volumeMounts[0].mountPath)|="\""$ACTIVITIES_DIR"\" |
yq "(.spec.template.spec.containers[0].image)|="\""$FULL_IMAGE"\" |
yq "(.spec.template.spec.containers[0].imagePullPolicy)|="\""$IMAGE_PULL_POLICY"\" |
yq "(.spec.template.spec.containers[0].ports[0].containerPort)|=$PORT" |
yq "(.spec.template.spec.containers[0].env[0].valueFrom.configMapKeyRef.name)|="\""$CONFIGMAP_NAME"\" |
yq "(.spec.template.spec.containers[0].env[1].valueFrom.secretKeyRef.name)|="\""$SECRET_NAME"\" |
yq "(.spec.template.spec.containers[0].volumeMounts[0].mountPath)|="\""$ACTIVITIES_DIR"\" |
kubectl apply -f -

# Create service
cat service.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.metadata.name)|="\""$SERVICE_NAME"\" |
kubectl apply -f -

# Wait for the rollout, so an unattended run of the scripts fails here instead of appearing to succeed
# while the pods are unable to mount the file share.
echo "Waiting for the [$DEPLOYMENT_NAME] deployment to roll out..."
kubectl rollout status "deployment/$DEPLOYMENT_NAME" --namespace "$NAMESPACE" --timeout=600s

if [[ $? == 0 ]]; then
	echo "The app is running. Browse to it with:"
	echo "  kubectl port-forward service/$SERVICE_NAME 8080:80 --namespace $NAMESPACE"
else
	echo "The [$DEPLOYMENT_NAME] deployment did not roll out. Inspect the pods with:"
	echo "  kubectl get pods --namespace $NAMESPACE"
	echo "  kubectl describe pod --selector app=$DEPLOYMENT_NAME --namespace $NAMESPACE"
	exit 1
fi
