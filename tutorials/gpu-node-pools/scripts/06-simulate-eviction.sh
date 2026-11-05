#!/bin/bash

# Step 6: send a longer training request and, once its job's pod reports training progress, simulate the eviction of
# its Spot node with az vmss simulate-eviction. As when Azure needs the capacity back, AKS taints the node
# remediator.kubernetes.azure.com/unschedulable:NoSchedule, evicts its pods and deletes the node with its scale set
# instance. The job then starts a replacement pod, which waits for the next node the cluster autoscaler adds and
# completes there. The message was deleted when the first pod received it, so the replacement pod finds the queue
# empty and trains for the default time.
# https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/use-spot#simulate-an-eviction

# Variables
source ./00-variables.sh
source ./functions.sh

KNOWN_JOBS=$(list_jobs)
send_training_request "$EVICTED_JOB_TRAIN_SECONDS" || exit 1

echo "Waiting for KEDA to start a job for the message..."
JOB=$(wait_for_new_job "$KNOWN_JOBS")
if [[ -z $JOB ]]; then
  echo "KEDA started no job within $JOB_START_TIMEOUT seconds"
  exit 1
fi
echo "Waiting for the pod of the [$JOB] job to run..."
RUNNING_NODE=$(wait_for_running_pod "$JOB")
if [[ -z $RUNNING_NODE ]]; then
  echo "No pod of the [$JOB] job runs after $JOB_START_TIMEOUT seconds"
  exit 1
fi
echo "The pod of the [$JOB] job runs on the [$RUNNING_NODE] node"

# A running pod may still be installing its libraries or receiving its message. Evict its node only once the pod
# trains, so that the eviction interrupts the training and the replacement pod finds the message already gone.
echo "Waiting for the pod of the [$JOB] job to report training progress..."
EVICTED_NODE=$(wait_for_training_progress "$JOB")
if [[ -z $EVICTED_NODE ]]; then
  echo "The pod of the [$JOB] job reported no training progress within $TRAINING_PROGRESS_TIMEOUT seconds. Its log:"
  print_job_logs "$JOB"
  exit 1
fi
echo "The pod of the [$JOB] job trains on the [$EVICTED_NODE] node"

# The node's provider id names its scale set instance:
# azure:///subscriptions/.../resourceGroups/<node resource group>/providers/Microsoft.Compute/virtualMachineScaleSets/<scale set>/virtualMachines/<instance id>
PROVIDER_ID=$(kubectl get node "$EVICTED_NODE" --output jsonpath='{.spec.providerID}')
INSTANCE_ID=${PROVIDER_ID##*/}
SCALE_SET_NAME=${PROVIDER_ID%/virtualMachines/*}
SCALE_SET_NAME=${SCALE_SET_NAME##*/}
NODE_RESOURCE_GROUP=$(az aks show \
  --name "$AKS_NAME" \
  --resource-group "$AKS_RESOURCE_GROUP_NAME" \
  --query nodeResourceGroup \
  --output tsv \
  --only-show-errors 2>/dev/null | tr -d '\r')
if [[ -z $INSTANCE_ID || -z $SCALE_SET_NAME || -z $NODE_RESOURCE_GROUP ]]; then
  echo "Failed to find the scale set instance behind the [$EVICTED_NODE] node (provider id [$PROVIDER_ID])"
  exit 1
fi

echo "Simulating the eviction of instance [$INSTANCE_ID] of the [$SCALE_SET_NAME] scale set..."
if ! az vmss simulate-eviction \
  --resource-group "$NODE_RESOURCE_GROUP" \
  --name "$SCALE_SET_NAME" \
  --instance-id "$INSTANCE_ID" \
  --only-show-errors; then
  echo "Failed to simulate the eviction of instance [$INSTANCE_ID] of the [$SCALE_SET_NAME] scale set"
  exit 1
fi

# Follow the evicted node until AKS deletes it, printing its taints once AKS adds the eviction taint. A failed kubectl
# call is retried; --ignore-not-found prints nothing once the node is gone.
TAINT_SEEN=""
NODE_DELETED=""
DEADLINE=$((SECONDS + NODE_DELETION_TIMEOUT))
EVICTION_START=$SECONDS
while ((SECONDS < DEADLINE)); do
  if NODE_TAINTS=$(kubectl get node "$EVICTED_NODE" \
    --ignore-not-found \
    --output jsonpath='{.metadata.name}{" "}{range .spec.taints[*]}{.key}={.value}:{.effect}{" "}{end}'); then
    if [[ -z $NODE_TAINTS ]]; then
      echo "The [$EVICTED_NODE] node was deleted $((SECONDS - EVICTION_START)) seconds after the eviction request"
      NODE_DELETED="yes"
      break
    fi
    if [[ -z $TAINT_SEEN && $NODE_TAINTS == *remediator.kubernetes.azure.com/unschedulable* ]]; then
      TAINT_SEEN="yes"
      echo "The [$EVICTED_NODE] node is tainted for the eviction: ${NODE_TAINTS#* }"
    fi
  fi
  sleep "$POLL_INTERVAL"
done
if [[ -z $NODE_DELETED ]]; then
  echo "The [$EVICTED_NODE] node still exists $NODE_DELETION_TIMEOUT seconds after the eviction request"
  exit 1
fi

echo "Waiting for the [$JOB] job to complete on a new node..."
if ! wait_for_job_completion "$JOB"; then
  echo "The [$JOB] job didn't complete:"
  print_job_logs "$JOB"
  exit 1
fi
COMPLETED_NODE=$(kubectl get pods \
  --namespace "$NAMESPACE" \
  --selector "job-name=$JOB" \
  --field-selector status.phase=Succeeded \
  --output jsonpath='{.items[0].spec.nodeName}')
if [[ -z $COMPLETED_NODE || $COMPLETED_NODE == "$EVICTED_NODE" ]]; then
  echo "The [$JOB] job completed, but not on a new node (node [$COMPLETED_NODE])"
  exit 1
fi
echo "The [$JOB] job completed on the [$COMPLETED_NODE] node after the eviction of [$EVICTED_NODE]:"
kubectl get pods --namespace "$NAMESPACE" --selector "job-name=$JOB" --output wide
print_job_logs "$JOB"
