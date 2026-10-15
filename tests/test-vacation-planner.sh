#!/bin/bash
# Check a deployed Vacation Planner sample end to end through its Kubernetes service:
# 1. the Deployment rolls out and GET /health reports the data service as reachable
# 2. adding an activity through the web form stores it, and the page lists it
# 3. deleting it through the web form removes it from the page
# It drives both versions of every sample: the Python (Flask) and the .NET (Razor Pages) web app.
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

PF_LOG=$(mktemp)
COOKIES=$(mktemp)
kubectl port-forward --namespace "$NAMESPACE" "service/$SERVICE" "$LOCAL_PORT:80" > "$PF_LOG" 2>&1 &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null || true; rm -f "$PF_LOG" "$COOKIES"' EXIT

# Wait until kubectl listens on LOCAL_PORT. If it exits instead (the port is taken, for example by a
# port-forward left running for another sample), stop rather than test whatever answers on that port.
until grep -q '^Forwarding from' "$PF_LOG"; do
  if ! kill -0 "$PF_PID" 2>/dev/null; then
    echo "Test failed: kubectl port-forward exited: $(cat "$PF_LOG")"
    exit 1
  fi
  sleep 1
done

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

# Talk to the app the way a browser does. The .NET apps are Razor Pages, which reject a form post without the
# antiforgery token the page renders and the cookie sent with it; the Python apps ignore both.
get_page() {
  curl -sS -m 30 -b "$COOKIES" -c "$COOKIES" "$BASE_URL/"
}

# Post a form and print the HTTP status: post_form <path> [<field>=<value>...]
post_form() {
  local path=$1 field
  shift
  local args=(-sS -m 30 -o /dev/null -w '%{http_code}' -b "$COOKIES" -c "$COOKIES" -X POST)
  for field in "$@"; do
    args+=(--data-urlencode "$field")
  done
  if [ -n "$token" ]; then
    args+=(--data-urlencode "__RequestVerificationToken=$token")
  fi
  curl "${args[@]}" "$BASE_URL$path"
}

# Print the id of the row that lists an activity on the last page fetched, or nothing.
# Each row carries the activity id and text: <tr data-id="<id>" data-activity="<text>">
row_id_of() {
  grep -o "data-id=\"[^\"]*\" data-activity=\"$1\"" <<< "$page" | sed 's/^data-id="\([^"]*\)".*/\1/' || true
}

# Most samples delete through POST /delete/<id>; the Azure Files sample posts the id to /delete
delete_activity() {
  if grep -q 'name="activity_id"' <<< "$page"; then
    post_form /delete "activity_id=$1"
  else
    post_form "/delete/$1"
  fi
}

page=$(get_page)
token=$(sed -n '/name="__RequestVerificationToken"/{s/.*name="__RequestVerificationToken" type="hidden" value="\([^"]*\)".*/\1/p;q;}' <<< "$page")

ACTIVITY="CI check $(date +%s)"
status=$(post_form / "activity=$ACTIVITY")
if [ "$status" != "302" ]; then
  echo "Test failed: adding an activity returned HTTP $status, expected a 302 redirect"
  exit 1
fi
page=$(get_page)
row_id=$(row_id_of "$ACTIVITY")
if [ -z "$row_id" ]; then
  echo "Test failed: the page does not list the activity '$ACTIVITY'"
  exit 1
fi
echo "PASS: added activity '$ACTIVITY' (id $row_id) and the page lists it"

# Keep a second activity listed while the first is deleted. An app that swallows a failed read renders an
# empty list rather than an error (the in-cluster and blob apps do), so without it the absence check below
# also passes on a page that lists nothing. The blob and Azure Files samples name each activity after the
# current second, so wait one first.
sleep 1
KEPT_ACTIVITY="CI keep $(date +%s)"
post_form / "activity=$KEPT_ACTIVITY" > /dev/null

status=$(delete_activity "$row_id")
if [ "$status" != "302" ]; then
  echo "Test failed: deleting the activity returned HTTP $status, expected a 302 redirect"
  exit 1
fi
page=$(get_page)
kept_id=$(row_id_of "$KEPT_ACTIVITY")
if [ -z "$kept_id" ]; then
  echo "Test failed: the page no longer lists '$KEPT_ACTIVITY', so it cannot show the deleted activity is gone"
  exit 1
fi
if [ -n "$(row_id_of "$ACTIVITY")" ]; then
  echo "Test failed: the activity is still listed after deleting it"
  exit 1
fi
echo "PASS: deleted the activity and the page no longer lists it"
delete_activity "$kept_id" > /dev/null || true

echo "Test passed: the Vacation Planner in [$NAMESPACE] stores, lists and deletes activities"
