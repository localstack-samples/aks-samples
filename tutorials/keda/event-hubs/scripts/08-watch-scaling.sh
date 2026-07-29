#!/bin/bash

# Step 8: prove that KEDA scaled the consumer on the consumer group's lag.
#
# Four checks: KEDA owns the workload, the consumer scaled out from zero, the consumer checkpointed its
# progress, and the consumer scaled back to zero. Each prints PASS or FAIL; on any failure the script
# dumps the KEDA operator log, the ScaledObject conditions, the autoscaler state and the namespace
# events, so the reason is diagnosable from the output alone.
#
# The third check is where this tutorial differs from the Service Bus one. Event Hubs exposes no ARM
# backlog counter, so there is no equivalent of the queue's activeMessageCount to poll: consumers do not
# remove events, they advance a cursor. The azure-eventhub scaler computes the lag itself, as the last
# enqueued sequence number minus the sequence number in the consumer group's checkpoint, which it reads
# from the CHECKPOINT_CONTAINER blob container. Those checkpoint blobs are therefore the meaningful
# assertion here: they are the very input the scaler uses, and without them the reported lag never falls
# and the Deployment can never scale back to zero.
#
# Run this right after 07-run-producer.sh: the scale-out is transient by design, because the consumer
# starts catching up as soon as the first replica is activated.

# Variables
source ./00-variables.sh

# How long to wait for each phase. Scale-out has to happen within the polling interval plus the
# time the HPA needs to observe the metric; scale-in additionally waits out the cooldown period.
SCALE_OUT_TIMEOUT_SECONDS=300
CHECKPOINT_TIMEOUT_SECONDS=600
SCALE_IN_TIMEOUT_SECONDS=600

FAILED=""

dump_diagnostics() {
  echo "----- diagnostics -----"
  echo "Scaled object:"
  kubectl describe scaledobject $SCALED_OBJECT_NAME --namespace $NAMESPACE 2>/dev/null | tail -25
  echo "Horizontal pod autoscaler:"
  kubectl describe hpa $HPA_NAME --namespace $NAMESPACE 2>/dev/null | tail -25
  echo "Deployment and pods:"
  kubectl get deployment,pod --namespace $NAMESPACE 2>/dev/null
  echo "Events:"
  kubectl get events --namespace $NAMESPACE --sort-by=.lastTimestamp 2>/dev/null | tail -15
  echo "KEDA operator log:"
  kubectl logs deployment/$KEDA_OPERATOR_DEPLOYMENT --namespace $KEDA_NAMESPACE --tail=40 2>/dev/null
  echo "-----------------------"
}

# Check 1: KEDA owns the workload
kubectl get hpa $HPA_NAME --namespace $NAMESPACE &>/dev/null
if [[ $? -eq 0 ]]; then
  echo "PASS: KEDA manages the [$DEPLOYMENT_NAME] deployment through the [$HPA_NAME] horizontal pod autoscaler"
else
  echo "FAIL: the [$HPA_NAME] horizontal pod autoscaler does not exist, so KEDA is not scaling the [$DEPLOYMENT_NAME] deployment"
  dump_diagnostics
  exit 1
fi

# Check 2: the consumer scales out from zero, one replica at a time.
#
# Both halves matter. Reaching MAX_REPLICAS proves the backlog was seen; getting there through
# intermediate steps proves the autoscaler is following the scaleUp policy rather than slamming into the
# cap, which is what the ramp in this sample is meant to show. The poll is faster than the policy period
# so no step can be missed, and every requested value is recorded rather than only the final one.
echo "Watching the [$DEPLOYMENT_NAME] deployment scale out (one replica per [$SCALE_UP_PERIOD_SECONDS]s, up to [$MAX_REPLICAS])..."
RAMP_POLL_SECONDS=2
OBSERVED_REPLICAS=0
OBSERVED_STEPS=""
STEP_COUNT=0
SCALED_OUT=""
for i in $(seq 1 $(($SCALE_OUT_TIMEOUT_SECONDS / $RAMP_POLL_SECONDS))); do
  DESIRED=$(kubectl get deployment $DEPLOYMENT_NAME \
    --namespace $NAMESPACE \
    --output jsonpath='{.spec.replicas}' 2>/dev/null)
  READY=$(kubectl get deployment $DEPLOYMENT_NAME \
    --namespace $NAMESPACE \
    --output jsonpath='{.status.readyReplicas}' 2>/dev/null)
  DESIRED=${DESIRED:-0}
  READY=${READY:-0}
  if [[ $DESIRED -gt $OBSERVED_REPLICAS ]]; then
    OBSERVED_REPLICAS=$DESIRED
    STEP_COUNT=$(($STEP_COUNT + 1))
    OBSERVED_STEPS="${OBSERVED_STEPS:+$OBSERVED_STEPS -> }$DESIRED"
    echo "The autoscaler now requests [$DESIRED] replicas ([$READY] ready)"
  fi
  if [[ $DESIRED -ge $MAX_REPLICAS ]]; then
    SCALED_OUT="true"
    break
  fi
  sleep $RAMP_POLL_SECONDS
done

echo "Observed scale-out: 0 -> $OBSERVED_STEPS"

if [[ -n $SCALED_OUT ]]; then
  echo "PASS: the [$DEPLOYMENT_NAME] deployment scaled out from zero to [$MAX_REPLICAS] replicas"
elif [[ $OBSERVED_REPLICAS -ge 2 ]]; then
  # The backlog drained while the ramp was still climbing, which is a legitimate outcome for a small
  # backlog: the scale-out is proven, it simply stopped short of the cap.
  echo "PASS: the [$DEPLOYMENT_NAME] deployment scaled out from zero to [$OBSERVED_REPLICAS] replicas before the backlog drained"
else
  echo "FAIL: the [$DEPLOYMENT_NAME] deployment did not scale beyond [$OBSERVED_REPLICAS] replicas"
  FAILED="true"
  dump_diagnostics
fi

# The ramp itself: with the scaleUp policy of one replica per period, going from zero to the cap has to
# take more than one step. A single step to the cap means the policy is not in effect.
if [[ $STEP_COUNT -ge 2 ]]; then
  echo "PASS: the scale-out was gradual, in [$STEP_COUNT] steps"
else
  echo "FAIL: the deployment reached [$OBSERVED_REPLICAS] replicas in a single step, so the scaleUp policy did not take effect"
  FAILED="true"
  kubectl describe hpa $HPA_NAME --namespace $NAMESPACE 2>/dev/null | sed -n '/Behavior:/,/Conditions:/p'
fi

# Check 3: the consumer checkpoints its progress. A missing or failed read never counts as success.
echo "Waiting for the consumer to write checkpoints into the [$CHECKPOINT_CONTAINER] container..."
CHECKPOINTED=""
CHECKPOINT_BLOBS=""

# Blob operations are data-plane calls and need a credential of their own
STORAGE_ACCOUNT_KEY=$(az storage account keys list \
  --account-name $STORAGE_ACCOUNT_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query "[0].value" \
  --output tsv \
  --only-show-errors 2>/dev/null)

if [[ -z $STORAGE_ACCOUNT_KEY ]]; then
  echo "Could not retrieve an access key of the [$STORAGE_ACCOUNT_NAME] storage account, so the checkpoints cannot be read"
else
  # The checkpoint store writes one blob per partition under
  # <namespace>/<hub>/<consumer group>/checkpoint/<partition id>, next to the ownership blobs it uses
  # for partition load balancing, so only the checkpoint ones count.
  for i in $(seq 1 $(($CHECKPOINT_TIMEOUT_SECONDS / $SLEEP))); do
    CHECKPOINT_BLOBS=$(az storage blob list \
      --container-name $CHECKPOINT_CONTAINER \
      --account-name $STORAGE_ACCOUNT_NAME \
      --account-key $STORAGE_ACCOUNT_KEY \
      --query "[].name" \
      --output tsv \
      --only-show-errors 2>/dev/null | grep "/checkpoint/")

    if [[ -n $CHECKPOINT_BLOBS ]]; then
      CHECKPOINTED="true"
      break
    fi
    sleep $SLEEP
  done
fi

if [[ -n $CHECKPOINTED ]]; then
  echo "PASS: the consumer checkpointed [$(echo "$CHECKPOINT_BLOBS" | wc -l)] partition(s) of the [$EVENT_HUB_CONSUMER_GROUP] consumer group in the [$CHECKPOINT_CONTAINER] container:"
  echo "$CHECKPOINT_BLOBS"
else
  echo "FAIL: no checkpoint blob was found in the [$CHECKPOINT_CONTAINER] container of the [$STORAGE_ACCOUNT_NAME] storage account"
  echo "The scaler computes the lag from these checkpoints, so without them the reported lag stays at its peak and the [$DEPLOYMENT_NAME] deployment cannot scale back to zero"
  FAILED="true"
  dump_diagnostics
fi

# Check 4: the consumer scales back to zero once it has caught up
echo "Waiting for the [$DEPLOYMENT_NAME] deployment to scale back to zero (cooldown is [$COOLDOWN_PERIOD]s)..."
SCALED_IN=""
for i in $(seq 1 $(($SCALE_IN_TIMEOUT_SECONDS / $SLEEP))); do
  DESIRED=$(kubectl get deployment $DEPLOYMENT_NAME \
    --namespace $NAMESPACE \
    --output jsonpath='{.spec.replicas}' 2>/dev/null)
  if [[ "$DESIRED" == "0" ]]; then
    SCALED_IN="true"
    break
  fi
  sleep $SLEEP
done

if [[ -n $SCALED_IN ]]; then
  echo "PASS: the [$DEPLOYMENT_NAME] deployment scaled back to zero replicas"
else
  echo "FAIL: the [$DEPLOYMENT_NAME] deployment still requests [${DESIRED:-unknown}] replicas"
  FAILED="true"
  dump_diagnostics
fi

if [[ -n $FAILED ]]; then
  echo "One or more checks failed"
  exit 1
fi

echo "SUCCESS: KEDA scaled the [$DEPLOYMENT_NAME] deployment from zero to [$OBSERVED_REPLICAS] replicas on the lag of the [$EVENT_HUB_CONSUMER_GROUP] consumer group of the [$EVENT_HUB_NAME] event hub and back to zero"
