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

# Check 3: the queue drains. A missing or failed read never counts as drained.
echo "Waiting for the [$SERVICE_BUS_QUEUE_NAME] queue to drain..."
DRAINED=""
for i in $(seq 1 $(($DRAIN_TIMEOUT_SECONDS / $SLEEP))); do
  # Both counts matter: a consumer that keeps crashing burns the queue's maxDeliveryCount and the
  # messages end up in the dead-letter queue, which empties activeMessageCount without any of the
  # work being done. Requiring deadLetterMessageCount to stay at zero is what stops that from
  # reading as a successful drain.
  # Queried separately on purpose: `--query "[a, b]" --output tsv` prints the two values on two
  # lines, not tab separated, so reading them as one record would produce a multi-line value.
  MESSAGE_BACKLOG=$(az servicebus queue show \
    --name $SERVICE_BUS_QUEUE_NAME \
    --namespace-name $SERVICE_BUS_NAMESPACE_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --query countDetails.activeMessageCount \
    --output tsv \
    --only-show-errors 2>/dev/null)
  DEAD_LETTERED=$(az servicebus queue show \
    --name $SERVICE_BUS_QUEUE_NAME \
    --namespace-name $SERVICE_BUS_NAMESPACE_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --query countDetails.deadLetterMessageCount \
    --output tsv \
    --only-show-errors 2>/dev/null)
  if [[ "$MESSAGE_BACKLOG" == "0" && "$DEAD_LETTERED" == "0" ]]; then
    DRAINED="true"
    break
  fi
  if [[ -n $DEAD_LETTERED && "$DEAD_LETTERED" != "0" ]]; then
    echo "FAIL: [$DEAD_LETTERED] message(s) were dead-lettered, so the consumer is failing to process them"
    break
  fi
  sleep $SLEEP
done

if [[ -n $DRAINED ]]; then
  echo "PASS: the consumer drained the [$SERVICE_BUS_QUEUE_NAME] queue with no dead-lettered messages"
else
  echo "FAIL: the [$SERVICE_BUS_QUEUE_NAME] queue reports [${MESSAGE_BACKLOG:-unknown}] active and [${DEAD_LETTERED:-unknown}] dead-lettered messages"
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

echo "SUCCESS: KEDA scaled the [$DEPLOYMENT_NAME] deployment from zero to [$OBSERVED_REPLICAS] replicas on the [$SERVICE_BUS_QUEUE_NAME] queue backlog and back to zero"
