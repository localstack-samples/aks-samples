#!/bin/bash

# Variables
source ./00-variables.sh

# The database runs in-cluster (statefulset.yml). Reach it from the host by
# port-forwarding the primary (write) Service to localhost:$PG_LOCAL_PORT.
# Requires 05-deploy-app.sh (deploys the DB) and 06-create-test-data.sh
# (creates PlannerDB + testuser) to have run first.
echo "Port-forwarding svc/$PG_PRIMARY_SERVICE to localhost:$PG_LOCAL_PORT..."
kubectl port-forward -n "$NAMESPACE" "svc/$PG_PRIMARY_SERVICE" "$PG_LOCAL_PORT:5432" &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null' EXIT

# Wait for the forwarded port to accept connections.
echo "Waiting for PostgreSQL to accept connections on localhost:$PG_LOCAL_PORT..."
until pg_isready -h localhost -p "$PG_LOCAL_PORT" -U "$PG_USER_NAME" &>/dev/null; do
	sleep 2
done

# --network=host so the container reaches the port-forward on the host's loopback.
docker run -it \
	--rm \
	--network=host \
	-e PORT=$PORT \
	-e PG_HOST="localhost" \
	-e PG_PORT="$PG_LOCAL_PORT" \
	-e PG_DATABASE="$PG_DATABASE_NAME" \
	-e PG_USER="$PG_USER_NAME" \
	-e PG_PASSWORD="$PG_USER_PASSWORD" \
	-e LOGIN_NAME="$LOGIN_NAME" \
	--name "$IMAGE_NAME" \
	"$IMAGE_NAME:$IMAGE_TAG"
