#!/bin/bash

# Variables
source ./00-variables.sh

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Generate a stable Flask SECRET_KEY (sessions survive pod restarts)
FLASK_SECRET_KEY=$(openssl rand -hex 32)

# Get the login server for the Azure Container Registry
echo "Getting login server for Azure Container Registry [$ACR_NAME]..."
ACR_LOGIN_SERVER=$(az acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "loginServer" \
	--output tsv \
	--only-show-errors)

if [ -n "$ACR_LOGIN_SERVER" ]; then
	echo "Login server retrieved successfully: $ACR_LOGIN_SERVER"
else
	echo "Failed to retrieve login server for Azure Container Registry [$ACR_NAME]."
	exit 1
fi

FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

# Create namespace
cat namespace.yml |
yq "(.metadata.name)|="\""$NAMESPACE"\" |
kubectl apply -f -

# Deploy the in-cluster PostgreSQL StatefulSet (primary + streaming replicas) and its
# secret/configmap/services. The namespace is injected into every document in the file.
echo "Deploying in-cluster PostgreSQL StatefulSet [$PG_STATEFULSET_NAME]..."
cat statefulset.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
kubectl apply -f -

# Wait for the StatefulSet (primary + replicas) to be ready before deploying the app.
echo "Waiting for PostgreSQL StatefulSet [$PG_STATEFULSET_NAME] to become ready..."
kubectl rollout status "statefulset/$PG_STATEFULSET_NAME" -n "$NAMESPACE" --timeout=600s

# ---------------------------------------------------------------------------
# Provision the application database/role and seed test data in the in-cluster
# PostgreSQL primary. Done here (before the app Deployment) so the app pods can
# authenticate as [$PG_USER_NAME] on first start. Connects over a port-forward to
# the primary (write) Service, so psql must be available on the host machine.
# ---------------------------------------------------------------------------
if ! command -v psql &>/dev/null; then
	echo "psql is not installed on the host. Install the PostgreSQL client (postgresql-client) and re-run."
	exit 1
fi

echo "Waiting for PostgreSQL primary pod [$PG_PRIMARY_POD] to be ready..."
kubectl wait --for=condition=ready "pod/$PG_PRIMARY_POD" -n "$NAMESPACE" --timeout=600s

echo "Port-forwarding svc/$PG_PRIMARY_SERVICE to localhost:$PG_LOCAL_PORT..."
kubectl port-forward -n "$NAMESPACE" "svc/$PG_PRIMARY_SERVICE" "$PG_LOCAL_PORT:5432" &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null' EXIT

echo "Waiting for PostgreSQL to accept connections on localhost:$PG_LOCAL_PORT..."
until pg_isready -h localhost -p "$PG_LOCAL_PORT" -U "$PG_SUPERUSER" &>/dev/null; do
	sleep 2
done

# Create the application database [$PG_DATABASE_NAME]. PostgreSQL has no
# CREATE DATABASE IF NOT EXISTS, so check for existence first (CREATE DATABASE
# also cannot run inside a DO block / transaction).
echo "Creating database [$PG_DATABASE_NAME]..."
DB_EXISTS=$(PGPASSWORD="$PG_SUPERUSER_PASSWORD" psql \
	--host=localhost \
	--port="$PG_LOCAL_PORT" \
	--username="$PG_SUPERUSER" \
	--dbname=postgres \
	--no-password \
	-tAc "SELECT 1 FROM pg_database WHERE datname = '$PG_DATABASE_NAME';")

if [ "$DB_EXISTS" != "1" ]; then
	PGPASSWORD="$PG_SUPERUSER_PASSWORD" psql \
		--host=localhost \
		--port="$PG_LOCAL_PORT" \
		--username="$PG_SUPERUSER" \
		--dbname=postgres \
		--no-password \
		--set=ON_ERROR_STOP=on \
		-c "CREATE DATABASE \"$PG_DATABASE_NAME\";"

	if [ $? -eq 0 ]; then
		echo "Database [$PG_DATABASE_NAME] created successfully"
	else
		echo "Failed to create database [$PG_DATABASE_NAME]"
		exit 1
	fi
else
	echo "Database [$PG_DATABASE_NAME] already exists"
fi

# Create the application login [$PG_USER_NAME].
echo "Creating login [$PG_USER_NAME]..."
PGPASSWORD="$PG_SUPERUSER_PASSWORD" psql \
	--host=localhost \
	--port="$PG_LOCAL_PORT" \
	--username="$PG_SUPERUSER" \
	--dbname=postgres \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "DO \$\$
BEGIN
	IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$PG_USER_NAME') THEN
		CREATE ROLE \"$PG_USER_NAME\" WITH LOGIN PASSWORD '$PG_USER_PASSWORD';
	END IF;
END
\$\$;"

if [ $? -eq 0 ]; then
	echo "Login [$PG_USER_NAME] created successfully"
else
	echo "Failed to create login [$PG_USER_NAME]"
	exit 1
fi

# Grant CONNECT on the database to [$PG_USER_NAME].
echo "Granting CONNECT on [$PG_DATABASE_NAME] to [$PG_USER_NAME]..."
PGPASSWORD="$PG_SUPERUSER_PASSWORD" psql \
	--host=localhost \
	--port="$PG_LOCAL_PORT" \
	--username="$PG_SUPERUSER" \
	--dbname=postgres \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "GRANT CONNECT ON DATABASE \"$PG_DATABASE_NAME\" TO \"$PG_USER_NAME\";"

if [ $? -eq 0 ]; then
	echo "CONNECT granted successfully to [$PG_USER_NAME]"
else
	echo "Failed to grant CONNECT to [$PG_USER_NAME]"
	exit 1
fi

# Grant schema privileges to [$PG_USER_NAME].
echo "Granting schema privileges on [$PG_DATABASE_NAME] to [$PG_USER_NAME]..."
PGPASSWORD="$PG_SUPERUSER_PASSWORD" psql \
	--host=localhost \
	--port="$PG_LOCAL_PORT" \
	--username="$PG_SUPERUSER" \
	--dbname="$PG_DATABASE_NAME" \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "GRANT USAGE, CREATE ON SCHEMA public TO \"$PG_USER_NAME\";
		ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO \"$PG_USER_NAME\";
		ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO \"$PG_USER_NAME\";"

if [ $? -eq 0 ]; then
	echo "Schema privileges granted successfully to [$PG_USER_NAME]"
else
	echo "Failed to grant schema privileges to [$PG_USER_NAME]"
	exit 1
fi

# Create [activities] table. The app also creates this on startup (init_schema);
# we create it here too so seeding does not race the application pods.
echo "Creating [activities] table in the [$PG_DATABASE_NAME] database..."
PGPASSWORD="$PG_USER_PASSWORD" psql \
	--host=localhost \
	--port="$PG_LOCAL_PORT" \
	--username="$PG_USER_NAME" \
	--dbname="$PG_DATABASE_NAME" \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "CREATE TABLE IF NOT EXISTS activities (
			id           TEXT PRIMARY KEY,
			username     TEXT NOT NULL,
			activity     TEXT NOT NULL,
			created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
		CREATE INDEX IF NOT EXISTS idx_activities_username ON activities(username);
		CREATE INDEX IF NOT EXISTS idx_activities_created_at ON activities(created_at DESC);"

if [ $? -eq 0 ]; then
	echo "[activities] table created successfully"
else
	echo "Failed to create [activities] table"
	exit 1
fi

# Insert sample data
echo "Inserting sample data into [activities] table..."
PGPASSWORD="$PG_USER_PASSWORD" psql \
	--host=localhost \
	--port="$PG_LOCAL_PORT" \
	--username="$PG_USER_NAME" \
	--dbname="$PG_DATABASE_NAME" \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "INSERT INTO activities (id, username, activity) VALUES
			(md5('paolo_pisa_seed'), 'paolo', 'Visit the Leaning Tower in Pisa'),
			(md5('paolo_volterra_seed'), 'paolo', 'Explore Etruscan walls in Volterra'),
			(md5('paolo_san_gimignano_seed'), 'paolo', 'Climb Torre Grossa in San Gimignano'),
			(md5('paolo_siena_seed'), 'paolo', 'Walk across Piazza del Campo in Siena'),
			(md5('paolo_montalcino_seed'), 'paolo', 'Taste Brunello wine in Montalcino'),
			(md5('paolo_pienza_seed'), 'paolo', 'Sample Pecorino cheese in Pienza'),
			(md5('paolo_florence_seed'), 'paolo', 'Admire Michelangelo''s David in Florence'),
			(md5('paolo_viareggio_beach_seed'), 'paolo', 'Relax by the beach in Viareggio'),
			(md5('paolo_viareggio_promenade_seed'), 'paolo', 'Stroll along the Viareggio promenade')
		ON CONFLICT (id) DO NOTHING;"

if [ $? -eq 0 ]; then
	echo "Test data inserted successfully into [activities] table"
else
	echo "Failed to insert test data into [activities] table"
	exit 1
fi

# Query data
echo "Querying test data from [activities] table..."
PGPASSWORD="$PG_USER_PASSWORD" psql \
	--host=localhost \
	--port="$PG_LOCAL_PORT" \
	--username="$PG_USER_NAME" \
	--dbname="$PG_DATABASE_NAME" \
	--no-password \
	-c "SELECT id, username, activity, created_at FROM activities;"

if [ $? -eq 0 ]; then
	echo "Test data queried successfully from [activities] table"
else
	echo "Failed to query test data from [activities] table"
	exit 1
fi

# Provisioning done — stop the port-forward before deploying the app.
kill "$PF_PID" 2>/dev/null
trap - EXIT

# Create secret with the PostgreSQL password and the Flask secret key
cat secret.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.data.PG_PASSWORD)|="\""$(echo -n $PG_USER_PASSWORD | base64 -w0)"\" |
yq "(.data.SECRET_KEY)|="\""$(echo -n $FLASK_SECRET_KEY | base64 -w0)"\" |
kubectl apply -f -

# Create configmap with environment variables. PG_HOST is the in-cluster write
# (primary) Service; the app does writes so it must not target a read replica.
cat configmap.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.data.PG_HOST)|="\""$PG_PRIMARY_SERVICE"\" |
yq "(.data.PG_PORT)|="\""$PG_PORT"\" |
yq "(.data.PG_DATABASE)|="\""$PG_DATABASE_NAME"\" |
yq "(.data.PG_USER)|="\""$PG_USER_NAME"\" |
yq "(.data.LOGIN_NAME)|="\""$LOGIN_NAME"\" |
kubectl apply -f -

# Create deployment
cat deployment.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.spec.template.spec.containers[0].image)|="\""$FULL_IMAGE"\" |
yq "(.spec.template.spec.containers[0].imagePullPolicy)|="\""$IMAGE_PULL_POLICY"\" |
yq "(.spec.template.spec.containers[0].ports[0].containerPort)|=$PORT" |
kubectl apply -f -

# Create service
cat service.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
kubectl apply -f -
