#!/bin/bash

# Runs the producer of all three KEDA tutorials at once.
#
# On its own, a tutorial's 07-run-producer.sh fills one backlog and one Deployment scales. Firing all
# three within a second or two of each other puts three independent backlogs in place at the same
# moment, so the three consumer Deployments ramp up and fall back to zero side by side and the whole
# story fits in a single k9s pane.
#
# Nothing here duplicates the tutorials. Each 07-run-producer.sh sources its own 00-variables.sh
# through a relative path and applies manifests from its own folder, so the only correct way to invoke
# one is with that folder as the working directory, which is what the subshells below do. Change a
# message count, a producer or a manifest in any tutorial and this script picks it up unedited.
#
# 08-watch-scaling.sh is deliberately not run: it is the assertion script, and it would spend several
# minutes narrating in the terminal the same scale-out k9s is already showing.
#
# Prerequisite: 06-deploy-consumer.sh must have been run for each tutorial, so the consumers and their
# ScaledObjects exist. This script checks that before sending anything.

# Every tutorial under this folder that has a producer to run. Order is irrelevant: they run together.
TUTORIALS=(service-bus queue-storage event-hubs)

# Resolve the tutorials/keda folder from this script's own location, so it works from any directory
KEDA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Each tutorial's output is captured rather than printed live: three producers writing to the same
# terminal at once interleave into something unreadable. The logs are replayed per tutorial afterwards.
LOG_DIR=$(mktemp -d)
trap 'rm -rf "$LOG_DIR"' EXIT

echo "Running the producers of [${#TUTORIALS[@]}] tutorials in parallel..."
echo

PIDS=()
for TUTORIAL in "${TUTORIALS[@]}"; do
  (
    cd "$KEDA_ROOT/$TUTORIAL/scripts" || exit 1

    # The tutorial's own variables, which is where NAMESPACE and DEPLOYMENT_NAME come from. Sourcing
    # them here rather than hardcoding the names is what keeps this script in step with the tutorials.
    source ./00-variables.sh

    # Record the target so the summary below can report on it without sourcing everything a second time
    echo "$NAMESPACE $DEPLOYMENT_NAME" >"$LOG_DIR/$TUTORIAL.target"

    # A backlog with no consumer deployed is not a demo: there is no ScaledObject to react to it and
    # the messages simply sit in the queue.
    if ! kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$NAMESPACE" &>/dev/null; then
      echo "The [$DEPLOYMENT_NAME] deployment does not exist in the [$NAMESPACE] namespace"
      echo "Run $TUTORIAL/scripts/06-deploy-consumer.sh first"
      exit 1
    fi

    ./07-run-producer.sh
  ) >"$LOG_DIR/$TUTORIAL.log" 2>&1 &
  PIDS+=($!)
done

# Collect each producer's exit status. wait on a specific pid returns that job's status, so a failure
# is attributed to the tutorial it came from rather than lost in an aggregate.
FAILED=""
for INDEX in "${!TUTORIALS[@]}"; do
  if ! wait "${PIDS[$INDEX]}"; then
    FAILED="${FAILED:+$FAILED }${TUTORIALS[$INDEX]}"
  fi
done

# Replay the logs: the last few lines on success, which is where the producer reports what it sent, and
# the whole thing on failure, where the reason is.
for TUTORIAL in "${TUTORIALS[@]}"; do
  echo "----- $TUTORIAL -----"
  if [[ " $FAILED " == *" $TUTORIAL "* ]]; then
    cat "$LOG_DIR/$TUTORIAL.log"
  else
    # The producer's closing line is the only one worth seeing here; the SDK chatter above it is not.
    # The tail is a fallback in case a producer ever stops printing that line.
    grep -m1 "Done:" "$LOG_DIR/$TUTORIAL.log" || tail -3 "$LOG_DIR/$TUTORIAL.log"
  fi
  echo
done

if [[ -n $FAILED ]]; then
  echo "FAIL: the producer of [$FAILED] did not complete, so that tutorial has no backlog to scale on"
  exit 1
fi

# Each Deployment is read on its own, because they live in three different namespaces, so the rows are
# collected and aligned in one pass rather than printed as three ragged lines.
echo "All [${#TUTORIALS[@]}] backlogs are in place and the consumers are scaling out now:"
{
  echo "NAMESPACE DEPLOYMENT READY UP-TO-DATE AVAILABLE AGE"
  for TUTORIAL in "${TUTORIALS[@]}"; do
    [[ -f "$LOG_DIR/$TUTORIAL.target" ]] || continue
    read -r NAMESPACE DEPLOYMENT_NAME <"$LOG_DIR/$TUTORIAL.target"
    ROW=$(kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$NAMESPACE" --no-headers 2>/dev/null)
    [[ -n $ROW ]] && echo "$NAMESPACE $ROW"
  done
} | column -t

# The three consumers are the only Deployments whose name ends in -consumer, which is what makes a
# single filter enough to watch all of them across their three namespaces.
echo
echo "Watch all three scale out and back to zero:"
echo "  k9s -A -c deployments        then filter with: /consumer"
echo "  watch -n 1 'kubectl get deployment --all-namespaces | grep -- -consumer'"
