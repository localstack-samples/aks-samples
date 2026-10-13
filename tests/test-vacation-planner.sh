#!/bin/bash
# Check a deployed Vacation Planner sample end to end through its Kubernetes service:
# 1. the Deployment rolls out and GET /health reports the data service as reachable
# 2. adding an activity through the web form stores it, and the page lists it
# 3. deleting it through the web form removes it from the page
#
# Usage: tests/test-vacation-planner.sh <namespace> <service> [deployment]
set -euo pipefail

NAMESPACE=$1
SERVICE=$2
DEPLOYMENT=${3:-$2}
LOCAL_PORT=${LOCAL_PORT:-8080}
MAX_ATTEMPTS=${MAX_ATTEMPTS:-60}
BASE_URL="http://localhost:$LOCAL_PORT"

kubectl rollout status "deployment/$DEPLOYMENT" --namespace "$NAMESPACE" --timeout=600s

kubectl port-forward --namespace "$NAMESPACE" "service/$SERVICE" "$LOCAL_PORT:80" > /dev/null 2>&1 &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null' EXIT

health=""
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  health=$(curl -s -m 10 "$BASE_URL/health" || true)
  echo "$health" | jq -e '.status == "ok"' > /dev/null 2>&1 && break
  echo "Attempt $attempt/$MAX_ATTEMPTS: /health returned '$health'"
  sleep 5
done
if ! echo "$health" | jq -e '.status == "ok"' > /dev/null 2>&1; then
  echo "Test failed: /health never reported ok"
  exit 1
fi
echo "PASS: /health reports the data service as reachable"

ACTIVITY="CI check $(date +%s)"
status=$(curl -s -m 30 -o /dev/null -w '%{http_code}' --data-urlencode "activity=$ACTIVITY" "$BASE_URL/")
if [ "$status" != "302" ]; then
  echo "Test failed: adding an activity returned HTTP $status, expected a 302 redirect"
  exit 1
fi

# Each row carries the activity id and text: <tr data-id="<id>" data-activity="<text>">
row_id=$(curl -s -m 30 "$BASE_URL/" | grep -o "data-id=\"[^\"]*\" data-activity=\"$ACTIVITY\"" | sed 's/^data-id="\([^"]*\)".*/\1/' || true)
if [ -z "$row_id" ]; then
  echo "Test failed: the page does not list the activity '$ACTIVITY'"
  exit 1
fi
echo "PASS: added activity '$ACTIVITY' (id $row_id) and the page lists it"

status=$(curl -s -m 30 -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/delete/$row_id")
if [ "$status" != "302" ]; then
  echo "Test failed: deleting the activity returned HTTP $status, expected a 302 redirect"
  exit 1
fi
if curl -s -m 30 "$BASE_URL/" | grep -q "data-activity=\"$ACTIVITY\""; then
  echo "Test failed: the activity is still listed after deleting it"
  exit 1
fi
echo "PASS: deleted the activity and the page no longer lists it"

echo "Test passed: the Vacation Planner in [$NAMESPACE] stores, lists and deletes activities"
