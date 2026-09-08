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

# Create the Azure Database for MySQL flexible server
echo "Checking if MySQL flexible server [$MYSQL_SERVER_NAME] exists..."
az mysql flexible-server show \
	--name "$MYSQL_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating MySQL flexible server [$MYSQL_SERVER_NAME]..."
	az mysql flexible-server create \
		--name "$MYSQL_SERVER_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--tier "$MYSQL_SKU_TIER" \
		--sku-name "$MYSQL_SKU_NAME" \
		--version "$MYSQL_VERSION" \
		--storage-size "$MYSQL_STORAGE_SIZE_GB" \
		--backup-retention "$MYSQL_BACKUP_RETENTION_DAYS" \
		--geo-redundant-backup Disabled \
		--admin-user "$MYSQL_ADMIN_USER" \
		--admin-password "$MYSQL_ADMIN_PASSWORD" \
		--public-access Enabled \
		--high-availability Disabled \
		--yes \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "MySQL flexible server [$MYSQL_SERVER_NAME] created."
	else
		echo "Failed to create MySQL flexible server [$MYSQL_SERVER_NAME]."
		exit 1
	fi
else
	echo "MySQL flexible server [$MYSQL_SERVER_NAME] already exists."
fi

# Add a permissive firewall rule (dev/test only)
echo "Ensuring firewall rule [$FIREWALL_RULE_NAME] exists on MySQL flexible server [$MYSQL_SERVER_NAME]..."
az mysql flexible-server firewall-rule create \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$MYSQL_SERVER_NAME" \
	--rule-name "$FIREWALL_RULE_NAME" \
	--start-ip-address 0.0.0.0 \
	--end-ip-address 255.255.255.255 \
	--only-show-errors 1>/dev/null

# Create the MySQL database
echo "Checking if MySQL database [$MYSQL_DATABASE_NAME] exists..."
az mysql flexible-server db show \
	--database-name "$MYSQL_DATABASE_NAME" \
	--server-name "$MYSQL_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating MySQL database [$MYSQL_DATABASE_NAME]..."
	az mysql flexible-server db create \
		--database-name "$MYSQL_DATABASE_NAME" \
		--server-name "$MYSQL_SERVER_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--charset utf8mb4 \
		--collation utf8mb4_unicode_ci \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "MySQL database [$MYSQL_DATABASE_NAME] created."
	else
		echo "Failed to create MySQL database [$MYSQL_DATABASE_NAME]."
		exit 1
	fi
else
	echo "MySQL database [$MYSQL_DATABASE_NAME] already exists."
fi

# Retrieve MySQL server FQDN
MYSQL_FQDN_FULL=$(az mysql flexible-server show \
	--name "$MYSQL_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "fullyQualifiedDomainName" \
	--output tsv)

if [ -z "$MYSQL_FQDN_FULL" ]; then
	echo "Failed to retrieve MySQL server FQDN."
	exit 1
fi

# Split host:port — the LocalStack emulator embeds the dynamically allocated TCP-proxy port
# directly in fullyQualifiedDomainName, mirroring the storage / container registry emulators.
# Real Azure returns just the bare host so MYSQL_PORT stays at the value from 00-variables.sh (3306).
MYSQL_FQDN="${MYSQL_FQDN_FULL%%:*}"
if [[ "$MYSQL_FQDN_FULL" == *:* ]]; then
	MYSQL_PORT="${MYSQL_FQDN_FULL##*:}"
fi
echo "MySQL host = $MYSQL_FQDN, port = $MYSQL_PORT"

# The mysql client must be available on the host machine for the bootstrap below.
if ! command -v mysql &>/dev/null; then
	echo "mysql is not installed on the host. Install the MySQL client (mysql-client) and re-run." >&2
	exit 1
fi

# Wait for the MySQL flexible server to accept connections.
# --ssl-mode=REQUIRED: Azure (and the LocalStack emulator) enforce require_secure_transport=ON,
# so every connection must negotiate TLS.
echo "Waiting for the [$MYSQL_SERVER_NAME] MySQL flexible server to accept connections..."
MYSQL_READY=0
for attempt in $(seq 1 30); do
	if MYSQL_PWD="$MYSQL_ADMIN_PASSWORD" mysql \
		--host="$MYSQL_FQDN" \
		--port="$MYSQL_PORT" \
		--user="$MYSQL_ADMIN_USER" \
		--protocol=TCP \
		--ssl-mode=REQUIRED \
		--connect-timeout=5 \
		-e "SELECT 1;" &>/dev/null; then
		MYSQL_READY=1
		echo "MySQL flexible server is accepting connections (attempt $attempt/30)"
		break
	fi
	echo "MySQL flexible server not ready yet (attempt $attempt/30)..."
	sleep 2
done

if [ "$MYSQL_READY" -ne 1 ]; then
	echo "MySQL flexible server did not become reachable after 30 attempts. Exiting."
	exit 1
fi

# Create the application user [$MYSQL_USER_NAME] and grant it access to the database
echo "Creating login [$MYSQL_USER_NAME] on the [$MYSQL_SERVER_NAME] MySQL flexible server..."
MYSQL_PWD="$MYSQL_ADMIN_PASSWORD" mysql \
	--host="$MYSQL_FQDN" \
	--port="$MYSQL_PORT" \
	--user="$MYSQL_ADMIN_USER" \
	--protocol=TCP \
	--ssl-mode=REQUIRED \
	-e "CREATE USER IF NOT EXISTS '$MYSQL_USER_NAME'@'%' IDENTIFIED BY '$MYSQL_USER_PASSWORD';
		GRANT ALL PRIVILEGES ON \`$MYSQL_DATABASE_NAME\`.* TO '$MYSQL_USER_NAME'@'%';
		FLUSH PRIVILEGES;"

if [ $? -eq 0 ]; then
	echo "Login [$MYSQL_USER_NAME] created successfully"
else
	echo "Failed to create login [$MYSQL_USER_NAME]"
	exit 1
fi

# Create [activities] table
echo "Creating [activities] table in the [$MYSQL_DATABASE_NAME] database..."
MYSQL_PWD="$MYSQL_USER_PASSWORD" mysql \
	--host="$MYSQL_FQDN" \
	--port="$MYSQL_PORT" \
	--user="$MYSQL_USER_NAME" \
	--protocol=TCP \
	--ssl-mode=REQUIRED \
	--database="$MYSQL_DATABASE_NAME" \
	-e "CREATE TABLE IF NOT EXISTS activities (
			id           VARCHAR(32)  NOT NULL,
			username     VARCHAR(255) NOT NULL,
			activity     TEXT         NOT NULL,
			created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			INDEX idx_activities_username (username),
			INDEX idx_activities_created_at (created_at DESC)
		);"

if [ $? -eq 0 ]; then
	echo "[activities] table created successfully"
else
	echo "Failed to create [activities] table"
	exit 1
fi

# Insert sample data
echo "Inserting sample data into [activities] table..."
MYSQL_PWD="$MYSQL_USER_PASSWORD" mysql \
	--host="$MYSQL_FQDN" \
	--port="$MYSQL_PORT" \
	--user="$MYSQL_USER_NAME" \
	--protocol=TCP \
	--ssl-mode=REQUIRED \
	--database="$MYSQL_DATABASE_NAME" \
	-e "INSERT IGNORE INTO activities (id, username, activity) VALUES
			(MD5('paolo_pisa_seed'), 'paolo', 'Visit the Leaning Tower in Pisa'),
			(MD5('paolo_volterra_seed'), 'paolo', 'Explore Etruscan walls in Volterra'),
			(MD5('paolo_san_gimignano_seed'), 'paolo', 'Climb Torre Grossa in San Gimignano'),
			(MD5('paolo_siena_seed'), 'paolo', 'Walk across Piazza del Campo in Siena'),
			(MD5('paolo_montalcino_seed'), 'paolo', 'Taste Brunello wine in Montalcino'),
			(MD5('paolo_pienza_seed'), 'paolo', 'Sample Pecorino cheese in Pienza'),
			(MD5('paolo_florence_seed'), 'paolo', 'Admire Michelangelo''s David in Florence'),
			(MD5('paolo_viareggio_beach_seed'), 'paolo', 'Relax by the beach in Viareggio'),
			(MD5('paolo_viareggio_promenade_seed'), 'paolo', 'Stroll along the Viareggio promenade');"

if [ $? -eq 0 ]; then
	echo "Test data inserted successfully into [activities] table"
else
	echo "Failed to insert test data into [activities] table"
	exit 1
fi

# Query data
echo "Querying test data from [activities] table..."
MYSQL_PWD="$MYSQL_USER_PASSWORD" mysql \
	--host="$MYSQL_FQDN" \
	--port="$MYSQL_PORT" \
	--user="$MYSQL_USER_NAME" \
	--protocol=TCP \
	--ssl-mode=REQUIRED \
	--database="$MYSQL_DATABASE_NAME" \
	-e "SELECT id, username, activity, created_at FROM activities;"

if [ $? -eq 0 ]; then
	echo "Test data queried successfully from [activities] table"
else
	echo "Failed to query test data from [activities] table"
	exit 1
fi
