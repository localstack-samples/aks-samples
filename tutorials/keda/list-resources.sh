#!/bin/bash

# Lists every Azure resource the three KEDA tutorials create, in one pass.
#
# Unlike run-producers.sh, which runs each tutorial's scripts in a subshell, this script needs the
# three tutorials' variables in its own shell at the same time. That has one consequence worth knowing:
# the three files do not use disjoint variable names. STORAGE_ACCOUNT_NAME is defined by both
# event-hubs (the checkpoint account) and queue-storage (the queue account), and ROLE, SECRET_NAME and
# TRIGGER_AUTHENTICATION_NAME are each defined by two of them, so whatever is sourced last silently
# wins. Every value that differs between tutorials is therefore snapshotted under a tutorial-specific
# name immediately after its file is sourced, before the next source can overwrite it.

# Resolve the tutorials/keda folder from this script's own location, so it works from any directory
KEDA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Shared values: cluster, resource group, registry
source "$KEDA_ROOT/00-variables.sh"

# Event Hubs: namespace, hub, and the storage account holding the consumer group's checkpoints
source "$KEDA_ROOT/event-hubs/scripts/00-variables.sh"
EVENT_HUBS_CHECKPOINT_ACCOUNT="$STORAGE_ACCOUNT_NAME"

# Queue Storage: the storage account and the queue itself
source "$KEDA_ROOT/queue-storage/scripts/00-variables.sh"
QUEUE_STORAGE_ACCOUNT="$STORAGE_ACCOUNT_NAME"

# Service Bus: namespace and queue. Nothing it defines collides with what is still needed above.
source "$KEDA_ROOT/service-bus/scripts/00-variables.sh"

# Every section is a title with a blank line above and below it, so the tables underneath stay
# legible. Wrapping that in a function keeps the blank lines out of the body: the alternative is a
# bare echo before and after each of the eight commands, which is two dozen lines of punctuation.
heading() {
	echo
	echo "$1"
	echo
}

heading "Listing the resources created by the KEDA tutorials in the [$AKS_RESOURCE_GROUP_NAME] resource group..."
az resource list \
	--resource-group $AKS_RESOURCE_GROUP_NAME \
	--output table \
	--only-show-errors

heading "Listing the [$AKS_NAME] AKS cluster..."
az aks show \
	--name $AKS_NAME \
	--resource-group $AKS_RESOURCE_GROUP_NAME \
	--output table \
	--only-show-errors

heading "Listing the [$EVENT_HUBS_NAMESPACE_NAME] Event Hubs namespace..."
az eventhubs namespace show \
	--name $EVENT_HUBS_NAMESPACE_NAME \
	--resource-group $AKS_RESOURCE_GROUP_NAME \
	--output table \
	--query "{Name:name,Location:location}" \
	--only-show-errors

# An event hub has no message count and no delivery count: it is a log, not a queue. What matters here
# is the partition count, because the azure-eventhub scaler clamps the lag it reports to
# partitionCount * unprocessedEventThreshold, which makes this number the consumer's scaling ceiling.
heading "Listing the [$EVENT_HUB_NAME] event hub in the [$EVENT_HUBS_NAMESPACE_NAME] Event Hubs namespace..."
az eventhubs eventhub show \
	--name $EVENT_HUB_NAME \
	--namespace-name $EVENT_HUBS_NAMESPACE_NAME \
	--resource-group $AKS_RESOURCE_GROUP_NAME \
	--output table \
	--query "{Name:name,PartitionCount:partitionCount,MessageRetentionInDays:messageRetentionInDays,Status:status,Location:location}" \
	--only-show-errors

# The checkpoint account, not the queue one: the two tutorials both call it STORAGE_ACCOUNT_NAME
heading "Listing the [$EVENT_HUBS_CHECKPOINT_ACCOUNT] storage account holding the Event Hubs checkpoints..."
az storage account show \
	--name $EVENT_HUBS_CHECKPOINT_ACCOUNT \
	--resource-group $AKS_RESOURCE_GROUP_NAME \
	--output table \
	--query "{Name:name,Location:location}" \
	--only-show-errors

heading "Listing the [$QUEUE_STORAGE_ACCOUNT] storage account..."
az storage account show \
	--name $QUEUE_STORAGE_ACCOUNT \
	--resource-group $AKS_RESOURCE_GROUP_NAME \
	--output table \
	--query "{Name:name,Location:location}" \
	--only-show-errors

heading "Listing the [$STORAGE_QUEUE_NAME] queue in the [$QUEUE_STORAGE_ACCOUNT] storage account..."
az storage queue list \
	--account-name $QUEUE_STORAGE_ACCOUNT \
	--auth-mode login \
	--output table \
	--only-show-errors

heading "Listing the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace..."
az servicebus namespace show \
	--name $SERVICE_BUS_NAMESPACE_NAME \
	--resource-group $AKS_RESOURCE_GROUP_NAME \
	--output table \
	--query "{Name:name,Location:location}" \
	--only-show-errors

heading "Listing the [$SERVICE_BUS_QUEUE_NAME] queue in the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace..."
az servicebus queue list \
	--namespace-name $SERVICE_BUS_NAMESPACE_NAME \
	--resource-group $AKS_RESOURCE_GROUP_NAME \
	--output table \
	--query "[].{Name:name,MessageCount:messageCount,Location:location,MaxDeliveryCount:maxDeliveryCount}" \
	--only-show-errors

echo
