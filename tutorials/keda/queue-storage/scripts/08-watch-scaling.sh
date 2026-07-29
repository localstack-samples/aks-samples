#!/bin/bash

# Step 8: prove that KEDA scaled the consumer on the queue backlog.
#
# Four checks: KEDA owns the workload, the consumer scaled out from zero, the queue drained, and the
# consumer scaled back to zero. Each prints PASS or FAIL; on any failure the script dumps the KEDA
# operator log, the ScaledObject conditions, the autoscaler state and the namespace events, so the
# reason is diagnosable from the output alone.
#
# Run this right after 07-run-producer.sh: the scale-out is transient by design, because the
# consumer starts draining the backlog as soon as the first replica is activated.

# Variables
source ./00-variables.sh

# How long to wait for each phase. Scale-out has to happen within the polling interval plus the
# time the HPA needs to observe the metric; scale-in additionally waits out the cooldown period.
SCALE_OUT_TIMEOUT_SECONDS=300
DRAIN_TIMEOUT_SECONDS=600
SCALE_IN_TIMEOUT_SECONDS=600

# The largest number of messages a single Peek Messages call may return
MAX_PEEK_MESSAGES=32

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

# Check 2: the consumer scales out from zero
echo "Waiting for the [$DEPLOYMENT_NAME] deployment to scale out (at least 2 ready replicas)..."
OBSERVED_REPLICAS=0
SCALED_OUT=""
for i in $(seq 1 $(($SCALE_OUT_TIMEOUT_SECONDS / $SLEEP))); do
  READY=$(kubectl get deployment $DEPLOYMENT_NAME \
    --namespace $NAMESPACE \
    --output jsonpath='{.status.readyReplicas}' 2>/dev/null)
  READY=${READY:-0}
  if [[ $READY -gt $OBSERVED_REPLICAS ]]; then
    OBSERVED_REPLICAS=$READY
    echo "The [$DEPLOYMENT_NAME] deployment has [$READY] ready replicas"
  fi
  if [[ $READY -ge 2 ]]; then
    SCALED_OUT="true"
    break
  fi
  sleep $SLEEP
done

if [[ -n $SCALED_OUT ]]; then
  echo "PASS: the [$DEPLOYMENT_NAME] deployment scaled out from zero to [$OBSERVED_REPLICAS] ready replicas"
else
  echo "FAIL: the [$DEPLOYMENT_NAME] deployment did not reach 2 ready replicas (highest observed: [$OBSERVED_REPLICAS])"
  FAILED="true"
  dump_diagnostics
fi

# Check 3: the queue drains. A missing or failed read never counts as drained.
#
# The az CLI does not surface a queue's approximate message count: `az storage queue metadata show`
# returns only the user-defined metadata. The backlog is therefore read with Peek Messages, which
# returns the messages at the front of the queue without altering their visibility. Peek only sees
# VISIBLE messages, so the ones a consumer replica is currently holding are not counted and this check
# can declare the queue drained slightly early. Check 4 is the strict gate: KEDA's own metric is the
# approximate message count, which does include the in-flight messages, so the deployment cannot scale
# back to zero until the queue is truly empty.
# https://learn.microsoft.com/en-us/rest/api/storageservices/peek-messages
#
# Authentication mirrors 03-create-resources.sh: Microsoft Entra first, an account key as an explicit
# fallback, resolved once before the polling loop.
# https://learn.microsoft.com/en-us/azure/storage/queues/authorize-data-operations-cli
QUEUE_AUTHENTICATION=(--auth-mode login)
az storage message peek \
  --queue-name $STORAGE_QUEUE_NAME \
  --account-name $STORAGE_ACCOUNT_NAME \
  --num-messages 1 \
  "${QUEUE_AUTHENTICATION[@]}" \
  --only-show-errors &>/dev/null

if [[ $? -ne 0 ]]; then
  echo "Microsoft Entra authentication to the queue endpoint of the [$STORAGE_ACCOUNT_NAME] storage account did not work"
  echo "Falling back to an account key. Grant your own principal the [$ROLE] role on the storage account to avoid this."

  STORAGE_ACCOUNT_KEY=$(az storage account keys list \
    --account-name $STORAGE_ACCOUNT_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --query "[0].value" \
    --output tsv \
    --only-show-errors 2>/dev/null)
  if [[ -n $STORAGE_ACCOUNT_KEY ]]; then
    QUEUE_AUTHENTICATION=(--account-key "$STORAGE_ACCOUNT_KEY")
  else
    echo "Failed to retrieve an access key of the [$STORAGE_ACCOUNT_NAME] storage account"
    QUEUE_AUTHENTICATION=()
  fi
fi

DRAINED=""
VISIBLE_MESSAGES=""
if [[ ${#QUEUE_AUTHENTICATION[@]} -eq 0 ]]; then
  echo "The backlog of the [$STORAGE_QUEUE_NAME] queue cannot be read, so it cannot be reported as drained"
else
  echo "Waiting for the [$STORAGE_QUEUE_NAME] queue to drain..."
  for i in $(seq 1 $(($DRAIN_TIMEOUT_SECONDS / $SLEEP))); do
    VISIBLE_MESSAGES=$(az storage message peek \
      --queue-name $STORAGE_QUEUE_NAME \
      --account-name $STORAGE_ACCOUNT_NAME \
      --num-messages $MAX_PEEK_MESSAGES \
      "${QUEUE_AUTHENTICATION[@]}" \
      --query "length(@)" \
      --output tsv \
      --only-show-errors 2>/dev/null)
    if [[ "$VISIBLE_MESSAGES" == "0" ]]; then
      DRAINED="true"
      break
    fi
    sleep $SLEEP
  done
fi

if [[ -n $DRAINED ]]; then
  echo "PASS: the consumer drained the [$STORAGE_QUEUE_NAME] queue"
else
  echo "FAIL: the [$STORAGE_QUEUE_NAME] queue still reports [${VISIBLE_MESSAGES:-unknown}] visible messages"
  FAILED="true"
  dump_diagnostics
fi

# Check 4: the consumer scales back to zero once the backlog is gone
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

echo "SUCCESS: KEDA scaled the [$DEPLOYMENT_NAME] deployment from zero to [$OBSERVED_REPLICAS] replicas on the [$STORAGE_QUEUE_NAME] queue backlog and back to zero"
