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

# Check 2: the consumer scales out from zero.
#
# The ceiling is maxReplicaCount. This scaler reports the active message count as it is, so the
# autoscaler asks for ceil(backlog / SCALING_THRESHOLD) replicas and nothing but MAX_REPLICAS bounds
# it. The Event Hubs tutorial is the exception worth knowing about: there the scaler clamps the lag it
# reports to the partition count, so its ceiling can be lower than maxReplicaCount and has to be
# derived.
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

echo "SUCCESS: KEDA scaled the [$DEPLOYMENT_NAME] deployment from zero to [$OBSERVED_REPLICAS] replicas on the [$SERVICE_BUS_QUEUE_NAME] queue backlog and back to zero"
