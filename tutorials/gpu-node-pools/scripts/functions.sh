# Functions shared by the scripts of the GPU node pools tutorial. Source it after 00-variables.sh.

# Read the Service Bus endpoints the clients use, from the endpoint the namespace reports, and set:
#  - SERVICE_BUS_HOST: the namespace's host name;
#  - SERVICE_BUS_CUSTOM_ENDPOINT: sb://<host>:<port> when the namespace's AMQP port isn't 443, else empty. Azure reports
#    https://<namespace>.servicebus.windows.net:443/, the emulator its own host and AMQP port, which a client that signs
#    in with Microsoft Entra ID reaches through a custom endpoint address;
#  - SERVICE_BUS_HTTPS_AUTHORITY and SERVICE_BUS_ENDPOINT_SUFFIX: where the HTTPS API answers, which the KEDA scaler
#    and the message sender use. It is served on the Azure Resource Manager port: 443 on Azure, the gateway port on the
#    emulator. The default port stays out of the authority, because a shared access signature signs the URI as written.
read_service_bus_endpoints() {
  local endpoint authority port resource_manager arm_port
  endpoint=$(az servicebus namespace show \
    --name "$SERVICE_BUS_NAMESPACE_NAME" \
    --resource-group "$AKS_RESOURCE_GROUP_NAME" \
    --query serviceBusEndpoint \
    --output tsv \
    --only-show-errors 2>/dev/null | tr -d '\r')
  if [[ -z $endpoint ]]; then
    echo "Failed to read the endpoint of the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace"
    return 1
  fi
  authority=${endpoint#*://}
  authority=${authority%%/*}
  SERVICE_BUS_HOST=${authority%%:*}
  port=443
  if [[ $authority == *:* ]]; then
    port=${authority##*:}
  fi
  SERVICE_BUS_CUSTOM_ENDPOINT=""
  if [[ $port != 443 ]]; then
    SERVICE_BUS_CUSTOM_ENDPOINT="sb://$SERVICE_BUS_HOST:$port"
  fi
  resource_manager=$(az cloud show --query endpoints.resourceManager --output tsv --only-show-errors | tr -d '\r')
  resource_manager=${resource_manager%/}
  arm_port=${resource_manager##*:}
  if [[ $arm_port == "$resource_manager" || $arm_port == */* ]]; then
    arm_port=443
  fi
  SERVICE_BUS_HTTPS_AUTHORITY=$SERVICE_BUS_HOST
  if [[ $arm_port != 443 ]]; then
    SERVICE_BUS_HTTPS_AUTHORITY="$SERVICE_BUS_HOST:$arm_port"
  fi
  SERVICE_BUS_ENDPOINT_SUFFIX=${SERVICE_BUS_HTTPS_AUTHORITY#"$SERVICE_BUS_NAMESPACE_NAME".}
}

# send_training_request SECONDS: send the message {"train_seconds": SECONDS} to the queue through the Service Bus HTTPS
# API, signed with a shared access signature of the namespace's authorization rule. Prints nothing about the key.
send_training_request() {
  local body key resource_uri expiry signature
  body="{\"train_seconds\": $1}"
  read_service_bus_endpoints || return 1
  key=$(az servicebus namespace authorization-rule keys list \
    --namespace-name "$SERVICE_BUS_NAMESPACE_NAME" \
    --resource-group "$AKS_RESOURCE_GROUP_NAME" \
    --name "$SERVICE_BUS_AUTHORIZATION_RULE" \
    --query primaryKey \
    --output tsv \
    --only-show-errors 2>/dev/null | tr -d '\r')
  if [[ -z $key ]]; then
    echo "Failed to read the key of the [$SERVICE_BUS_AUTHORIZATION_RULE] rule of the [$SERVICE_BUS_NAMESPACE_NAME] namespace"
    return 1
  fi
  resource_uri=$(jq -rn --arg value "https://$SERVICE_BUS_HTTPS_AUTHORITY/$SERVICE_BUS_QUEUE_NAME" '$value | @uri')
  expiry=$(($(date +%s) + 3600))
  signature=$(printf '%s\n%s' "$resource_uri" "$expiry" |
    openssl dgst -sha256 -hmac "$key" -binary |
    openssl base64 -A |
    jq -rRn 'input | @uri')
  echo "Sending the message $body to the [$SERVICE_BUS_QUEUE_NAME] queue..."
  if ! curl --silent --show-error --fail-with-body --request POST \
    --header "Authorization: SharedAccessSignature sr=$resource_uri&sig=$signature&se=$expiry&skn=$SERVICE_BUS_AUTHORIZATION_RULE" \
    --header "Content-Type: application/json" \
    --data "$body" \
    "https://$SERVICE_BUS_HTTPS_AUTHORITY/$SERVICE_BUS_QUEUE_NAME/messages" >/dev/null; then
    echo "Failed to send a message to the [$SERVICE_BUS_QUEUE_NAME] queue"
    return 1
  fi
  echo "The message was sent to the [$SERVICE_BUS_QUEUE_NAME] queue"
}

# Print the names of the jobs the ScaledJob created, oldest first
list_jobs() {
  kubectl get jobs \
    --namespace "$NAMESPACE" \
    --selector "scaledjob.keda.sh/name=$SCALED_JOB_NAME" \
    --sort-by .metadata.creationTimestamp \
    --output jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null
}

# wait_for_new_job KNOWN_JOBS: wait until the ScaledJob creates a job that isn't in KNOWN_JOBS (one name per line),
# and print its name
wait_for_new_job() {
  local known_jobs=$1 deadline job
  deadline=$((SECONDS + JOB_START_TIMEOUT))
  while ((SECONDS < deadline)); do
    for job in $(list_jobs); do
      if ! printf '%s\n' "$known_jobs" | grep -qxF "$job"; then
        echo "$job"
        return 0
      fi
    done
    sleep "$POLL_INTERVAL"
  done
  return 1
}

# wait_for_running_pod JOB: wait until a pod of JOB runs, and print the node it runs on. While the pod is pending, the
# cluster autoscaler is adding a node to the GPU pool, and its status says why when it doesn't.
wait_for_running_pod() {
  local job=$1 deadline node phase
  deadline=$((SECONDS + JOB_START_TIMEOUT))
  while ((SECONDS < deadline)); do
    node=$(kubectl get pods \
      --namespace "$NAMESPACE" \
      --selector "job-name=$job" \
      --field-selector status.phase=Running \
      --output jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
    if [[ -n $node ]]; then
      echo "$node"
      return 0
    fi
    phase=$(kubectl get pods \
      --namespace "$NAMESPACE" \
      --selector "job-name=$job" \
      --output jsonpath='{.items[*].status.phase}' 2>/dev/null)
    echo "Waiting for a pod of the [$job] job to run (pods: ${phase:-none yet})..." >&2
    sleep "$POLL_INTERVAL"
  done
  return 1
}

# wait_for_job_completion JOB: wait until JOB completes; fail as soon as it fails
wait_for_job_completion() {
  local job=$1 deadline conditions
  deadline=$((SECONDS + JOB_TIMEOUT))
  while ((SECONDS < deadline)); do
    conditions=$(kubectl get job "$job" \
      --namespace "$NAMESPACE" \
      --output jsonpath='{range .status.conditions[?(@.status=="True")]}{.type}{" "}{end}' 2>/dev/null)
    case " $conditions " in
    *" Complete "*) return 0 ;;
    *" Failed "*) return 1 ;;
    esac
    sleep "$POLL_INTERVAL"
  done
  return 1
}

# print_gpu_node NODE: print the labels AKS gives a GPU node of a Spot pool, its taints and the GPUs it advertises
print_gpu_node() {
  local node=$1
  echo "The [$node] node:"
  kubectl get node "$node" --output json | jq '{
    name: .metadata.name,
    labels: (.metadata.labels | with_entries(select(.key | test("accelerator|agentpool$|scalesetpriority|priority$|instance-type$|topology.kubernetes.io|^workload$")))),
    taints: [.spec.taints[]? | "\(.key)=\(.value // ""):\(.effect)"],
    gpus: .status.allocatable["nvidia.com/gpu"]
  }'
}

# print_job_logs JOB: print the logs of the job's pods
print_job_logs() {
  kubectl logs \
    --namespace "$NAMESPACE" \
    --selector "job-name=$1" \
    --tail=-1 \
    --prefix 2>/dev/null
}
