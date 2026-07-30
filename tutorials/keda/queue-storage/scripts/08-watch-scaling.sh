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

# Check 2: the consumer scales out from zero.
#
# The ceiling is maxReplicaCount. This scaler reports the queue depth as it is, so the autoscaler asks
# for ceil(backlog / SCALING_THRESHOLD) replicas and nothing but MAX_REPLICAS bounds it. The Event Hubs
# tutorial is the exception worth knowing about: there the scaler clamps the lag it reports to the
# partition count, so its ceiling can be lower than maxReplicaCount and it has to be derived.
EXPECTED_REPLICAS=$MAX_REPLICAS

echo "Watching the [$DEPLOYMENT_NAME] deployment scale out (one replica per [$SCALE_UP_PERIOD_SECONDS]s, up to [$EXPECTED_REPLICAS])..."
RAMP_POLL_SECONDS=1
OBSERVED_REPLICAS=0
OBSERVED_STEPS=""
STEP_COUNT=0
SCALED_OUT=""
SCALED_IN=""
for i in $(seq 1 $(($SCALE_OUT_TIMEOUT_SECONDS / $RAMP_POLL_SECONDS))); do
  # One read rather than two, so the desired and ready counts come from the same object revision
  read DESIRED READY <<<"$(kubectl get deployment $DEPLOYMENT_NAME \
    --namespace $NAMESPACE \
    --output jsonpath='{.spec.replicas} {.status.readyReplicas}' 2>/dev/null)"
  DESIRED=${DESIRED:-0}
  READY=${READY:-0}
  if [[ $DESIRED -gt $OBSERVED_REPLICAS ]]; then
    OBSERVED_REPLICAS=$DESIRED
    STEP_COUNT=$(($STEP_COUNT + 1))
    OBSERVED_STEPS="${OBSERVED_STEPS:+$OBSERVED_STEPS -> }$DESIRED"
    echo "The autoscaler now requests [$DESIRED] replicas ([$READY] ready)"
  fi
  if [[ $DESIRED -ge $EXPECTED_REPLICAS ]]; then
    SCALED_OUT="true"
    break
  fi
  # The backlog can drain before the ramp reaches the ceiling, and once KEDA has deactivated the
  # workload nothing will move again. Without this the loop has no reason to stop and spends the rest
  # of its budget polling a Deployment that is already back at zero, which looks like a hang.
  if [[ $OBSERVED_REPLICAS -gt 0 && $DESIRED -eq 0 ]]; then
    SCALED_IN="true"
    break
  fi
  sleep $RAMP_POLL_SECONDS
done

echo "Observed scale-out: 0 -> ${OBSERVED_STEPS:-0}"

if [[ -n $SCALED_OUT ]]; then
  echo "PASS: the [$DEPLOYMENT_NAME] deployment scaled out from zero to [$OBSERVED_REPLICAS] replicas"
elif [[ $OBSERVED_REPLICAS -ge 2 ]]; then
  # The backlog drained while the ramp was still climbing, which is a legitimate outcome for a small
  # backlog: the scale-out is proven, it simply stopped short of the ceiling.
  echo "PASS: the [$DEPLOYMENT_NAME] deployment scaled out from zero to [$OBSERVED_REPLICAS] replicas before the backlog drained"
else
  echo "FAIL: the [$DEPLOYMENT_NAME] deployment did not scale beyond [$OBSERVED_REPLICAS] replicas"
  FAILED="true"
  dump_diagnostics
fi

# The ramp itself. KEDA activates the workload on its own, from zero to one, through its scale executor
# and not through the autoscaler, so the scaleUp policy governs only the steps above the first: there
# are EXPECTED_REPLICAS - 1 of them. Requiring a gradual climb is meaningful only when at least two of
# those steps exist, otherwise a correctly working sample would be reported as a failure.
HPA_STEPS=$(($EXPECTED_REPLICAS - 1))
if [[ $HPA_STEPS -lt 2 ]]; then
  echo "SKIP: the ceiling of [$EXPECTED_REPLICAS] replicas leaves the autoscaler a single step above KEDA's activation, so there is no ramp to be gradual"
elif [[ $STEP_COUNT -ge 2 ]]; then
  echo "PASS: the scale-out was gradual, in [$STEP_COUNT] steps"
else
  echo "FAIL: the deployment reached [$OBSERVED_REPLICAS] replicas in a single step, so the scaleUp policy did not take effect"
  FAILED="true"
  kubectl describe hpa $HPA_NAME --namespace $NAMESPACE 2>/dev/null | sed -n '/Behavior:/,/Conditions:/p'
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

# Check 4: the consumer scales back to zero once the backlog is gone.
#
# The scale-in may already have been seen by the ramp loop above, which watches the same Deployment and
# stops as soon as it returns to zero. In that case there is nothing left to wait for.
if [[ -n $SCALED_IN ]]; then
  echo "The [$DEPLOYMENT_NAME] deployment was already back to zero while the scale-out was being watched"
else
  echo "Waiting for the [$DEPLOYMENT_NAME] deployment to scale back to zero (cooldown is [$COOLDOWN_PERIOD]s)..."
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
fi

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
