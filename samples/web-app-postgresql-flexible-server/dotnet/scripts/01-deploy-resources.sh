#!/bin/bash

# Variables
source ./00-variables.sh

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Create a resource group
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]..."
az group show --name $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating resource group [$RESOURCE_GROUP_NAME]..."
	az group create \
		--name $RESOURCE_GROUP_NAME \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "Resource group [$RESOURCE_GROUP_NAME] created."
	else
		echo "Failed to create resource group [$RESOURCE_GROUP_NAME]."
		exit 1
	fi
else
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists."
fi

# Create the Azure Container Registry
echo "Checking if [$ACR_NAME] Azure Container Registry exists..."
az acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating Azure Container Registry [$ACR_NAME]..."
	az acr create \
		--name "$ACR_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--sku "$ACR_SKU" \
		--admin-enabled "true" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Azure Container Registry [$ACR_NAME] created."
	else
		echo "Failed to create Azure Container Registry [$ACR_NAME]."
		exit 1
	fi
else
	echo "[$ACR_NAME] Azure Container Registry already exists."
fi

# Create the Azure Database for PostgreSQL flexible server
echo "Checking if PostgreSQL flexible server [$PG_SERVER_NAME] exists..."
az postgres flexible-server show \
	--name "$PG_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating PostgreSQL flexible server [$PG_SERVER_NAME]..."
	az postgres flexible-server create \
		--name "$PG_SERVER_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--admin-user "$PG_ADMIN_USER" \
		--admin-password "$PG_ADMIN_PASSWORD" \
		--version "$PG_VERSION" \
		--tier "$PG_SKU_TIER" \
		--sku-name "$PG_SKU_NAME" \
		--storage-size "$PG_STORAGE_SIZE_GB" \
		--backup-retention "$PG_BACKUP_RETENTION_DAYS" \
		--public-access Enabled \
		--yes \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "PostgreSQL flexible server [$PG_SERVER_NAME] created."
	else
		echo "Failed to create PostgreSQL flexible server [$PG_SERVER_NAME]."
		exit 1
	fi
else
	echo "PostgreSQL flexible server [$PG_SERVER_NAME] already exists."
fi

# Add a permissive firewall rule (dev/test only)
echo "Ensuring firewall rule [$FIREWALL_RULE_NAME] exists on PostgreSQL flexible server [$PG_SERVER_NAME]..."
az postgres flexible-server firewall-rule create \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--server-name "$PG_SERVER_NAME" \
	--name "$FIREWALL_RULE_NAME" \
	--start-ip-address 0.0.0.0 \
	--end-ip-address 255.255.255.255 \
	--only-show-errors 1>/dev/null

# Create the PostgreSQL database
echo "Checking if PostgreSQL database [$PG_DATABASE_NAME] exists..."
az postgres flexible-server db show \
	--name "$PG_DATABASE_NAME" \
	--server-name "$PG_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating PostgreSQL database [$PG_DATABASE_NAME]..."
	az postgres flexible-server db create \
		--name "$PG_DATABASE_NAME" \
		--server-name "$PG_SERVER_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--charset UTF8 \
		--collation en_US.utf8 \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "PostgreSQL database [$PG_DATABASE_NAME] created."
	else
		echo "Failed to create PostgreSQL database [$PG_DATABASE_NAME]."
		exit 1
	fi
else
	echo "PostgreSQL database [$PG_DATABASE_NAME] already exists."
fi

# Retrieve PostgreSQL server FQDN
PG_FQDN_FULL=$(az postgres flexible-server show \
	--name "$PG_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "fullyQualifiedDomainName" \
	--output tsv)

if [ -z "$PG_FQDN_FULL" ]; then
	echo "Failed to retrieve PostgreSQL server FQDN."
	exit 1
fi

# Split host:port — the LocalStack emulator embeds the dynamically allocated TCP-proxy port
# directly in fullyQualifiedDomainName, mirroring the storage / container registry emulators.
# Real Azure returns just the bare host so PG_PORT stays at the value from 00-variables.sh (5432).
PG_FQDN="${PG_FQDN_FULL%%:*}"
if [[ "$PG_FQDN_FULL" == *:* ]]; then
	PG_PORT="${PG_FQDN_FULL##*:}"
fi
echo "PostgreSQL host = $PG_FQDN, port = $PG_PORT"

# Create application role + grants + schema + seed data.
# psql must be available on the host machine.
if ! command -v psql &>/dev/null; then
	echo "psql is not installed on the host. Install the PostgreSQL client (postgresql-client) and re-run."
	exit 1
fi

echo "Creating login [$PG_USER_NAME] on the [$PG_SERVER_NAME] PostgreSQL flexible server..."
PGPASSWORD="$PG_ADMIN_PASSWORD" psql \
	--host="$PG_FQDN" \
	--port="$PG_PORT" \
	--username="$PG_ADMIN_USER" \
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

# Grant CONNECT on the database to [$PG_USER_NAME]
echo "Granting CONNECT on [$PG_DATABASE_NAME] to [$PG_USER_NAME]..."
PGPASSWORD="$PG_ADMIN_PASSWORD" psql \
	--host="$PG_FQDN" \
	--port="$PG_PORT" \
	--username="$PG_ADMIN_USER" \
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

# Grant schema privileges to [$PG_USER_NAME]
echo "Granting schema privileges on [$PG_DATABASE_NAME] to [$PG_USER_NAME]..."
PGPASSWORD="$PG_ADMIN_PASSWORD" psql \
	--host="$PG_FQDN" \
	--port="$PG_PORT" \
	--username="$PG_ADMIN_USER" \
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

# Create [activities] table
echo "Creating [activities] table in the [$PG_DATABASE_NAME] database..."
PGPASSWORD="$PG_USER_PASSWORD" psql \
	--host="$PG_FQDN" \
	--port="$PG_PORT" \
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
	--host="$PG_FQDN" \
	--port="$PG_PORT" \
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
	--host="$PG_FQDN" \
	--port="$PG_PORT" \
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
