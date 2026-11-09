#!/bin/bash

# Step 5: send a training request and follow the job KEDA starts for it. The job's pod asks for one GPU, which no
# running node has: it stays Pending until the cluster autoscaler adds a node to the Spot GPU pool, the only pool whose
# nodes can run it, or starts again the node an earlier run left deallocated, which still has the job's image. The
# script prints that node's AKS labels, taints and GPUs, waits for the job to complete and prints its log, which says
# whether PyTorch found CUDA: on Azure it trains on the NVIDIA GPU, on the LocalStack emulator, whose GPU nodes
# advertise a GPU without one behind it, on the CPU.

# Variables
source ./00-variables.sh
source ./functions.sh

KNOWN_JOBS=$(list_jobs)
send_training_request "$FIRST_JOB_TRAIN_SECONDS" || exit 1

echo "Waiting for KEDA to start a job for the message..."
JOB=$(wait_for_new_job "$KNOWN_JOBS")
if [[ -z $JOB ]]; then
  echo "KEDA started no job within $JOB_START_TIMEOUT seconds; the ScaledJob and the operator's log say why:"
  kubectl describe scaledjob "$SCALED_JOB_NAME" --namespace "$NAMESPACE"
  kubectl logs "deployment/$KEDA_OPERATOR_DEPLOYMENT" --namespace "$KEDA_NAMESPACE" --tail=30
  exit 1
fi
echo "KEDA started the [$JOB] job"

echo "Waiting for the cluster autoscaler to add or start a node in the [$GPU_NODE_POOL_NAME] node pool and for the job's pod to run..."
NODE=$(wait_for_running_pod "$JOB")
if [[ -z $NODE ]]; then
  echo "No pod of the [$JOB] job runs after $JOB_START_TIMEOUT seconds. Its events, and the cluster autoscaler's status"
  echo "on Azure, say why: when Azure has no Spot capacity for [$GPU_NODE_VM_SIZE], the pool gets no node."
  kubectl describe pods --namespace "$NAMESPACE" --selector "job-name=$JOB" | tail -20
  kubectl get configmap cluster-autoscaler-status --namespace kube-system --output jsonpath='{.data.status}' 2>/dev/null
  exit 1
fi
echo "The pod of the [$JOB] job runs on the [$NODE] node"
print_gpu_node "$NODE"

echo "Waiting for the [$JOB] job to complete..."
if ! wait_for_job_completion "$JOB"; then
  echo "The [$JOB] job didn't complete:"
  print_job_logs "$JOB"
  exit 1
fi
echo "The [$JOB] job completed. Its log:"
print_job_logs "$JOB"
echo "Once its node is idle, the cluster autoscaler deallocates it: the GPU pool is back to zero nodes, and the next run"
echo "starts the node again, with the job's image already on its disk."
