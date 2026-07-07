#!/bin/bash

# Step 4: verify traffic actually routes through the gateway. The LoadBalancer EXTERNAL-IP the
# emulated CCM assigns is synthetic (not routable from the host), so the data path is exercised via
# kubectl port-forward against the NGF per-Gateway data-plane Service, with an explicit Host header.
# A request for the claimed hostname must return 200 from the echo-server; a request for an
# unclaimed hostname must NOT return 200 (proving the gateway makes the routing decision).

# Variables
source ./00-variables.sh

# Check whether jq is installed (used to pretty-print the echo-server response)
if ! command -v jq &>/dev/null; then
	echo "The [jq] command is required to pretty-print the echo-server response"
	
	# Install jq on Ubuntu/Debian: sudo apt install -y jq
	sudo apt install -y jq
fi

# Discover the NGF data-plane Service: NGF provisions it in the Gateway's namespace when the
# Gateway is Programmed, labelled with the gateway name (observed on the live Service).
NGF_DATAPLANE_SERVICE=$(kubectl get svc -n $NAMESPACE \
  -l "gateway.networking.k8s.io/gateway-name=$GATEWAY_NAME" -o name 2>/dev/null | head -1)
if [[ -z $NGF_DATAPLANE_SERVICE ]]; then
  echo "Could not find the NGF data-plane service in the [$NAMESPACE] namespace"
  echo "Run ./03-deploy-echoserver.sh first"
  exit 1
fi
echo "Discovered the NGF data-plane service: [$NGF_DATAPLANE_SERVICE]"

# Gateway "Programmed" reports accepted configuration, NOT data-plane readiness: the NGF
# per-Gateway nginx pod may still be pulling its image. A port-forward against a Service with no
# ready endpoints dies immediately, so wait for the data-plane pods (labelled with the gateway
# name) to be Ready first.
echo "Waiting for the NGF data-plane pods to be Ready..."
kubectl wait -n $NAMESPACE --for=condition=Ready pod \
  -l "gateway.networking.k8s.io/gateway-name=$GATEWAY_NAME" --timeout=${TIMEOUT_SECONDS}s
if [[ $? -ne 0 ]]; then
  echo "The NGF data-plane pods did not become Ready within $TIMEOUT_SECONDS seconds"
  exit 1
fi

# Start the port-forward and always stop it on exit
echo "Starting kubectl port-forward [$NGF_DATAPLANE_SERVICE] on local port [$PORT_FORWARD_LOCAL_PORT]..."
kubectl port-forward -n $NAMESPACE $NGF_DATAPLANE_SERVICE ${PORT_FORWARD_LOCAL_PORT}:80 &>/dev/null &
PORT_FORWARD_PID=$!
trap 'kill $PORT_FORWARD_PID &>/dev/null' EXIT

# The claimed hostname must reach the echo-server (retry while the forward and the data plane warm up)
echo "Sending a request for host [$SAMPLE_HOSTNAME] through the gateway..."
HTTP_CODE=""
ELAPSED=0
while true; do
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $SAMPLE_HOSTNAME" "http://127.0.0.1:${PORT_FORWARD_LOCAL_PORT}/" 2>/dev/null)
  if [[ "$HTTP_CODE" == "200" ]]; then
    break
  fi
  if [[ $ELAPSED -ge $TIMEOUT_SECONDS ]]; then
    break
  fi
  sleep $SLEEP
  ELAPSED=$((ELAPSED + SLEEP))
done
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "PASS: host [$SAMPLE_HOSTNAME] returned HTTP 200 through the gateway"
else
  echo "FAIL: host [$SAMPLE_HOSTNAME] returned HTTP [$HTTP_CODE] through the gateway"
  exit 1
fi

# An unclaimed hostname must not reach the backend
UNCLAIMED_HOSTNAME="unclaimed.local"
echo "Sending a request for the unclaimed host [$UNCLAIMED_HOSTNAME] through the gateway..."
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $UNCLAIMED_HOSTNAME" "http://127.0.0.1:${PORT_FORWARD_LOCAL_PORT}/" 2>/dev/null)
if [[ "$HTTP_CODE" != "200" ]]; then
  echo "PASS: unclaimed host [$UNCLAIMED_HOSTNAME] returned HTTP [$HTTP_CODE] (not routed to the backend)"
else
  echo "FAIL: unclaimed host [$UNCLAIMED_HOSTNAME] unexpectedly returned HTTP 200"
  exit 1
fi

# Show a full echo-server response for reference
echo "Sample response from the echo-server through the gateway:"
curl -s -H "Host: $SAMPLE_HOSTNAME" "http://127.0.0.1:${PORT_FORWARD_LOCAL_PORT}/" 2>/dev/null | jq -r '.'
echo
echo "All routing checks passed"
