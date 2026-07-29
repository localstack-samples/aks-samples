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

# Merge the cluster credentials into kubeconfig and set it as the current context
az aks get-credentials \
  --name $AKS_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --overwrite-existing \
  --only-show-errors 1>/dev/null
if [[ $? -ne 0 ]]; then
  echo "FAIL: could not merge the credentials for the [$AKS_NAME] AKS cluster"
  exit 1
fi

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
echo "Waiting for the [$SERVICE_BUS_QUEUE_NAME] queue to drain..."
DRAINED=""
for i in $(seq 1 $(($DRAIN_TIMEOUT_SECONDS / $SLEEP))); do
  MESSAGE_BACKLOG=$(az servicebus queue show \
    --name $SERVICE_BUS_QUEUE_NAME \
    --namespace-name $SERVICE_BUS_NAMESPACE_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --query countDetails.activeMessageCount \
    --output tsv \
    --only-show-errors 2>/dev/null)
  if [[ "$MESSAGE_BACKLOG" == "0" ]]; then
    DRAINED="true"
    break
  fi
  sleep $SLEEP
done

if [[ -n $DRAINED ]]; then
  echo "PASS: the consumer drained the [$SERVICE_BUS_QUEUE_NAME] queue"
else
  echo "FAIL: the [$SERVICE_BUS_QUEUE_NAME] queue still reports [${MESSAGE_BACKLOG:-unknown}] active messages"
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
