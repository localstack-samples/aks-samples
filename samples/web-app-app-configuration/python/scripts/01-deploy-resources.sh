#!/bin/bash

# Variables
source ./00-variables.sh

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

#********************************************
# Helper functions
#********************************************

# Assign a role to a principal on a scope, unless it already has it. Azure needs a moment to propagate a
# freshly created principal, so the create is retried.
# $1: the principal (object) id  $2: the principal type  $3: the role  $4: the scope
# $5: a description of the principal  $6: a description of the scope
ensure_role_assignment() {
	local principal_id=$1
	local principal_type=$2
	local role=$3
	local scope=$4
	local principal_description=$5
	local scope_description=$6
	local current attempt

	echo "Checking if the $principal_description has the [$role] role assignment on the $scope_description..."
	current=$(az role assignment list \
		--assignee "$principal_id" \
		--scope "$scope" \
		--query "[?roleDefinitionName=='$role'].roleDefinitionName" \
		--output tsv \
		--only-show-errors 2>/dev/null)

	if [[ $current == "$role" ]]; then
		echo "The $principal_description already has the [$role] role assignment on the $scope_description"
		return 0
	fi

	echo "Assigning the [$role] role to the $principal_description on the $scope_description..."
	for attempt in $(seq 1 "$ROLE_ASSIGNMENT_RETRY_COUNT"); do
		if az role assignment create \
			--assignee-object-id "$principal_id" \
			--assignee-principal-type "$principal_type" \
			--role "$role" \
			--scope "$scope" \
			--only-show-errors 1>/dev/null; then
			echo "[$role] role successfully assigned to the $principal_description on the $scope_description"
			return 0
		fi

		if [ "$attempt" -lt "$ROLE_ASSIGNMENT_RETRY_COUNT" ]; then
			echo "Attempt $attempt of $ROLE_ASSIGNMENT_RETRY_COUNT to assign the [$role] role failed; retrying in $ROLE_ASSIGNMENT_RETRY_SLEEP seconds..."
			sleep "$ROLE_ASSIGNMENT_RETRY_SLEEP"
		fi
	done

	echo "Failed to assign the [$role] role to the $principal_description on the $scope_description"
	exit 1
}

# Store a secret in the key vault, unless it already holds the same value. The value is never printed.
# Reads and writes go through the Key Vault data plane, which the deploying principal can use only once its
# Key Vault Secrets Officer assignment has propagated, so the write is retried.
# $1: the secret name  $2: the secret value
set_secret() {
	local secret_name=$1
	local secret_value=$2
	local current attempt

	echo "Checking if the [$secret_name] secret actually exists in the [$KEY_VAULT_NAME] key vault..."
	current=$(az keyvault secret show \
		--vault-name "$KEY_VAULT_NAME" \
		--name "$secret_name" \
		--query value \
		--output tsv \
		--only-show-errors 2>/dev/null)

	if [[ -n $current && $current == "$secret_value" ]]; then
		echo "The [$secret_name] secret already holds the expected value in the [$KEY_VAULT_NAME] key vault"
		return 0
	fi

	echo "Setting the [$secret_name] secret in the [$KEY_VAULT_NAME] key vault..."
	for attempt in $(seq 1 "$SECRET_RETRY_COUNT"); do
		if az keyvault secret set \
			--vault-name "$KEY_VAULT_NAME" \
			--name "$secret_name" \
			--value "$secret_value" \
			--only-show-errors 1>/dev/null; then
			echo "The [$secret_name] secret was successfully set in the [$KEY_VAULT_NAME] key vault"
			return 0
		fi

		if [ "$attempt" -lt "$SECRET_RETRY_COUNT" ]; then
			echo "Attempt $attempt of $SECRET_RETRY_COUNT to set the [$secret_name] secret failed (the [$KEY_VAULT_SECRETS_OFFICER_ROLE] assignment may still be propagating); retrying in $SECRET_RETRY_SLEEP seconds..."
			sleep "$SECRET_RETRY_SLEEP"
		fi
	done

	echo "Failed to set the [$secret_name] secret in the [$KEY_VAULT_NAME] key vault"
	exit 1
}

# The versionless identifier of a key vault secret: the id returned by `az keyvault secret set` with its
# trailing version segment removed. A reference built on it always resolves to the latest version, so
# rotating the secret needs no change in the store.
# $1: the secret name
secret_identifier() {
	local secret_name=$1
	local id

	id=$(az keyvault secret show \
		--vault-name "$KEY_VAULT_NAME" \
		--name "$secret_name" \
		--query id \
		--output tsv \
		--only-show-errors 2>/dev/null)

	if [[ -z $id ]]; then
		echo "Failed to retrieve the identifier of the [$secret_name] secret" >&2
		exit 1
	fi

	echo "${id%/*}"
}

# Set a plain key-value in the App Configuration store, unless it already holds the same value.
# $1: the key  $2: the value
set_key_value() {
	local key=$1
	local value=$2
	local current

	echo "Checking if the [$key] key actually exists in the [$APP_CONFIG_NAME] App Configuration store..."
	current=$(az appconfig kv show \
		--name "$APP_CONFIG_NAME" \
		--key "$key" \
		--query value \
		--output tsv \
		--only-show-errors 2>/dev/null)

	if [[ $? == 0 && $current == "$value" ]]; then
		echo "The [$key] key already holds the [$value] value in the [$APP_CONFIG_NAME] App Configuration store"
		return 0
	fi

	echo "Setting the [$key] key to the [$value] value in the [$APP_CONFIG_NAME] App Configuration store..."
	if az appconfig kv set \
		--name "$APP_CONFIG_NAME" \
		--key "$key" \
		--value "$value" \
		--yes \
		--only-show-errors 1>/dev/null; then
		echo "The [$key] key was successfully set to the [$value] value"
	else
		echo "Failed to set the [$key] key in the [$APP_CONFIG_NAME] App Configuration store"
		exit 1
	fi
}

# Set a Key Vault reference in the App Configuration store, unless it already points at the same secret.
# A Key Vault reference is a key-value whose content type is
# application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8 and whose value is {"uri":"<identifier>"}.
# $1: the key  $2: the versionless secret identifier
set_key_vault_reference() {
	local key=$1
	local secret_id=$2
	local current

	echo "Checking if the [$key] key actually exists in the [$APP_CONFIG_NAME] App Configuration store..."
	current=$(az appconfig kv show \
		--name "$APP_CONFIG_NAME" \
		--key "$key" \
		--query "join('|', [contentType, value])" \
		--output tsv \
		--only-show-errors 2>/dev/null)

	if [[ $current == "$KEY_VAULT_REFERENCE_CONTENT_TYPE|"*"\"$secret_id\""* ]]; then
		echo "The [$key] key already references the [$secret_id] secret"
		return 0
	fi

	echo "Setting the [$key] key as a reference to the [$secret_id] secret..."
	if az appconfig kv set-keyvault \
		--name "$APP_CONFIG_NAME" \
		--key "$key" \
		--secret-identifier "$secret_id" \
		--yes \
		--only-show-errors 1>/dev/null; then
		echo "The [$key] key was successfully set as a reference to the [$secret_id] secret"
	else
		echo "Failed to set the [$key] key in the [$APP_CONFIG_NAME] App Configuration store"
		exit 1
	fi
}

#********************************************
# Resource group
#********************************************

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

#********************************************
# Azure Container Registry
#********************************************

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

#********************************************
# User-assigned managed identity
#********************************************

echo "Checking if [$MANAGED_IDENTITY_NAME] managed identity actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating [$MANAGED_IDENTITY_NAME] managed identity in the [$RESOURCE_GROUP_NAME] resource group..."
	az identity create \
		--name "$MANAGED_IDENTITY_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$MANAGED_IDENTITY_NAME] managed identity successfully created"
	else
		echo "Failed to create [$MANAGED_IDENTITY_NAME] managed identity"
		exit 1
	fi
else
	echo "[$MANAGED_IDENTITY_NAME] managed identity already exists"
fi

CLIENT_ID=$(az identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query clientId \
	--output tsv \
	--only-show-errors)

PRINCIPAL_ID=$(az identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query principalId \
	--output tsv \
	--only-show-errors)

if [[ -z $CLIENT_ID || -z $PRINCIPAL_ID ]]; then
	echo "Failed to retrieve the clientId and principalId of the [$MANAGED_IDENTITY_NAME] managed identity"
	exit 1
fi

echo "[$MANAGED_IDENTITY_NAME] managed identity: clientId [$CLIENT_ID], principalId [$PRINCIPAL_ID]"

#********************************************
# Azure Database for PostgreSQL flexible server
#********************************************

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
# This script owns the split, because it is what writes PG_HOST and PG_PORT into the App Configuration
# store; 05-deploy-app.sh never touches them.
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
			(md5('paolo_pisa_seed'), '$LOGIN_NAME', 'Visit the Leaning Tower in Pisa'),
			(md5('paolo_volterra_seed'), '$LOGIN_NAME', 'Explore Etruscan walls in Volterra'),
			(md5('paolo_san_gimignano_seed'), '$LOGIN_NAME', 'Climb Torre Grossa in San Gimignano'),
			(md5('paolo_siena_seed'), '$LOGIN_NAME', 'Walk across Piazza del Campo in Siena'),
			(md5('paolo_montalcino_seed'), '$LOGIN_NAME', 'Taste Brunello wine in Montalcino'),
			(md5('paolo_pienza_seed'), '$LOGIN_NAME', 'Sample Pecorino cheese in Pienza'),
			(md5('paolo_florence_seed'), '$LOGIN_NAME', 'Admire Michelangelo''s David in Florence'),
			(md5('paolo_viareggio_beach_seed'), '$LOGIN_NAME', 'Relax by the beach in Viareggio'),
			(md5('paolo_viareggio_promenade_seed'), '$LOGIN_NAME', 'Stroll along the Viareggio promenade')
		ON CONFLICT (id) DO NOTHING;"

if [ $? -eq 0 ]; then
	echo "Test data inserted successfully into [activities] table"
else
	echo "Failed to insert test data into [activities] table"
	exit 1
fi

#********************************************
# Azure Key Vault
#********************************************

# The vault's own location, not $LOCATION: a soft-deleted vault stays in the region it was deleted in,
# so recovering (or purging) it with a different region fails.
DELETED_KEY_VAULT_LOCATION=$(az keyvault list-deleted \
	--query "[?name=='$KEY_VAULT_NAME'].properties.location | [0]" \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $DELETED_KEY_VAULT_LOCATION ]]; then
	echo "[$KEY_VAULT_NAME] key vault exists in a soft-deleted state in [$DELETED_KEY_VAULT_LOCATION]"
	echo "Recovering the [$KEY_VAULT_NAME] key vault..."

	az keyvault recover \
		--name "$KEY_VAULT_NAME" \
		--location "$DELETED_KEY_VAULT_LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? != 0 ]]; then
		echo "Failed to recover the soft-deleted [$KEY_VAULT_NAME] key vault"
		echo "Purge it and re-run this script:"
		echo "  az keyvault purge --name $KEY_VAULT_NAME --location $DELETED_KEY_VAULT_LOCATION"
		exit 1
	fi
	echo "[$KEY_VAULT_NAME] key vault successfully recovered"
fi

echo "Checking if [$KEY_VAULT_NAME] key vault actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az keyvault show \
	--name "$KEY_VAULT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating [$KEY_VAULT_NAME] key vault in the [$RESOURCE_GROUP_NAME] resource group..."

	# The Azure RBAC permission model: the Key Vault Secrets User role assigned to the managed identity
	# below only works on vaults that use it, not on vaults with access policies.
	az keyvault create \
		--name "$KEY_VAULT_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--enable-rbac-authorization true \
		--retention-days "$KEY_VAULT_RETENTION_DAYS" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$KEY_VAULT_NAME] key vault successfully created"
	else
		echo "Failed to create [$KEY_VAULT_NAME] key vault"
		exit 1
	fi
else
	echo "[$KEY_VAULT_NAME] key vault already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

KEY_VAULT_ID=$(az keyvault show \
	--name "$KEY_VAULT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -z $KEY_VAULT_ID ]]; then
	echo "Failed to retrieve the resource id of the [$KEY_VAULT_NAME] key vault"
	exit 1
fi

#********************************************
# The deploying principal needs to write the secrets
#********************************************

# Writing a secret goes through the Key Vault data plane, so the account running this script needs a
# data-plane role of its own. Resolve its object id: a user through the signed-in-user endpoint, a service
# principal through its app id, and if Microsoft Graph is not readable (common for a pipeline principal),
# from the oid claim of the CLI's own access token.
ACCOUNT_USER_NAME=$(az account show --query user.name --output tsv --only-show-errors)
ACCOUNT_USER_TYPE=$(az account show --query user.type --output tsv --only-show-errors)

if [[ $ACCOUNT_USER_TYPE == "user" ]]; then
	DEPLOYER_PRINCIPAL_TYPE="User"
	DEPLOYER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv --only-show-errors 2>/dev/null)
else
	DEPLOYER_PRINCIPAL_TYPE="ServicePrincipal"
	DEPLOYER_OBJECT_ID=$(az ad sp show --id "$ACCOUNT_USER_NAME" --query id --output tsv --only-show-errors 2>/dev/null)
fi

if [[ -z $DEPLOYER_OBJECT_ID ]]; then
	DEPLOYER_OBJECT_ID=$(az account get-access-token --query accessToken --output tsv --only-show-errors 2>/dev/null |
		cut -d. -f2 | tr '_-' '/+' | awk '{ pad = length($0) % 4; if (pad == 2) $0 = $0 "=="; else if (pad == 3) $0 = $0 "="; print }' |
		base64 -d 2>/dev/null | jq -r '.oid // empty' 2>/dev/null)
fi

if [[ -n $DEPLOYER_OBJECT_ID ]]; then
	echo "Deploying principal [$ACCOUNT_USER_NAME] ($DEPLOYER_PRINCIPAL_TYPE) has object id [$DEPLOYER_OBJECT_ID]"
	ensure_role_assignment "$DEPLOYER_OBJECT_ID" "$DEPLOYER_PRINCIPAL_TYPE" "$KEY_VAULT_SECRETS_OFFICER_ROLE" \
		"$KEY_VAULT_ID" "deploying principal [$ACCOUNT_USER_NAME]" "[$KEY_VAULT_NAME] key vault"
else
	echo "WARNING: could not resolve the object id of the deploying principal [$ACCOUNT_USER_NAME]; the [$KEY_VAULT_SECRETS_OFFICER_ROLE] role on the [$KEY_VAULT_NAME] key vault must already be assigned to it"
fi

#********************************************
# Secrets
#********************************************

# The database credentials. The pods never see these values from a manifest: they arrive through the App
# Configuration Key Vault references resolved by the provider.
set_secret "$PG_USER_SECRET_NAME" "$PG_USER_NAME"
set_secret "$PG_PASSWORD_SECRET_NAME" "$PG_USER_PASSWORD"

# The Flask session key. Generated once and then kept: a new key on every run would leave the running pods
# signing with the old one, so sessions and flash messages break across replicas until every pod restarts.
SECRET_KEY_VALUE=$(az keyvault secret show \
	--vault-name "$KEY_VAULT_NAME" \
	--name "$SECRET_KEY_SECRET_NAME" \
	--query value \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -z $SECRET_KEY_VALUE ]]; then
	echo "No [$SECRET_KEY_SECRET_NAME] secret yet: generating one"
	SECRET_KEY_VALUE=$(openssl rand -hex 32)
fi

set_secret "$SECRET_KEY_SECRET_NAME" "$SECRET_KEY_VALUE"

# || exit 1 on every call: the function's own `exit 1` only leaves the command substitution's
# subshell, so without this the script would carry on with an empty identifier.
PG_USER_SECRET_ID=$(secret_identifier "$PG_USER_SECRET_NAME") || exit 1
PG_PASSWORD_SECRET_ID=$(secret_identifier "$PG_PASSWORD_SECRET_NAME") || exit 1
SECRET_KEY_SECRET_ID=$(secret_identifier "$SECRET_KEY_SECRET_NAME") || exit 1

#********************************************
# Azure App Configuration
#********************************************

# Deleting a Standard store only soft-deletes it and the name stays reserved for the retention period, so
# re-running this script after deleting the resource group would fail the create below.
DELETED_APP_CONFIG_LOCATION=$(az appconfig list-deleted \
	--query "[?name=='$APP_CONFIG_NAME'].location | [0]" \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $DELETED_APP_CONFIG_LOCATION ]]; then
	echo "[$APP_CONFIG_NAME] App Configuration store exists in a soft-deleted state in [$DELETED_APP_CONFIG_LOCATION]"
	echo "Recovering the [$APP_CONFIG_NAME] App Configuration store..."

	az appconfig recover \
		--name "$APP_CONFIG_NAME" \
		--location "$DELETED_APP_CONFIG_LOCATION" \
		--yes \
		--only-show-errors 1>/dev/null

	if [[ $? != 0 ]]; then
		echo "Failed to recover the soft-deleted [$APP_CONFIG_NAME] App Configuration store"
		echo "Purge it and re-run this script:"
		echo "  az appconfig purge --name $APP_CONFIG_NAME --location $DELETED_APP_CONFIG_LOCATION --yes"
		exit 1
	fi
	echo "[$APP_CONFIG_NAME] App Configuration store successfully recovered"
fi

echo "Checking if [$APP_CONFIG_NAME] App Configuration store actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az appconfig show \
	--name "$APP_CONFIG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating [$APP_CONFIG_NAME] App Configuration store in the [$RESOURCE_GROUP_NAME] resource group..."

	# Access keys stay enabled (the default): the az appconfig kv commands below authenticate with them.
	# The provider in the cluster never uses them, it authenticates with Microsoft Entra Workload ID.
	az appconfig create \
		--name "$APP_CONFIG_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--sku "$APP_CONFIG_SKU" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$APP_CONFIG_NAME] App Configuration store successfully created"
	else
		echo "Failed to create [$APP_CONFIG_NAME] App Configuration store"
		exit 1
	fi
else
	echo "[$APP_CONFIG_NAME] App Configuration store already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# The endpoint is read back from the service, never assembled from the name: it is
# https://<store>.azconfig.io on Azure and https://<store>.azure.localhost.localstack.cloud:4566 on the
# emulator. 05-deploy-app.sh reads it the same way for the custom resource.
APP_CONFIG_ID=$(az appconfig show \
	--name "$APP_CONFIG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

APP_CONFIG_ENDPOINT=$(az appconfig show \
	--name "$APP_CONFIG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query endpoint \
	--output tsv \
	--only-show-errors)

if [[ -z $APP_CONFIG_ID || -z $APP_CONFIG_ENDPOINT ]]; then
	echo "Failed to retrieve the resource id and endpoint of the [$APP_CONFIG_NAME] App Configuration store"
	exit 1
fi

echo "[$APP_CONFIG_NAME] App Configuration endpoint: $APP_CONFIG_ENDPOINT"

#********************************************
# Key-values and Key Vault references
#********************************************

# Plain key-values. Every key is flat and colon-free on purpose: the provider turns each one into a
# ConfigMap or Secret data key, and a key such as Settings:Color is not a legal Kubernetes data key.
set_key_value "PG_HOST" "$PG_FQDN"
set_key_value "PG_PORT" "$PG_PORT"
set_key_value "PG_DATABASE" "$PG_DATABASE_NAME"
set_key_value "LOGIN_NAME" "$LOGIN_NAME"
set_key_value "DEBUG" "false"

# The refresh sentinel is written only when it does not exist yet, so a manual bump used to demonstrate
# dynamic configuration is not undone by the next run of this script.
CURRENT_SENTINEL=$(az appconfig kv show \
	--name "$APP_CONFIG_NAME" \
	--key "$SENTINEL_KEY" \
	--query value \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -z $CURRENT_SENTINEL ]]; then
	set_key_value "$SENTINEL_KEY" "$SENTINEL_INITIAL_VALUE"
else
	echo "The [$SENTINEL_KEY] sentinel key already holds the [$CURRENT_SENTINEL] value: left untouched"
fi

# Key Vault references. The identifiers carry no version, so rotating a secret is followed automatically.
set_key_vault_reference "PG_USER" "$PG_USER_SECRET_ID"
set_key_vault_reference "PG_PASSWORD" "$PG_PASSWORD_SECRET_ID"
set_key_vault_reference "SECRET_KEY" "$SECRET_KEY_SECRET_ID"

#********************************************
# Role assignments of the managed identity
#********************************************

# What the provider needs, and nothing more: read the key-values, and resolve the references.
ensure_role_assignment "$PRINCIPAL_ID" "ServicePrincipal" "$APP_CONFIG_DATA_READER_ROLE" \
	"$APP_CONFIG_ID" "[$MANAGED_IDENTITY_NAME] managed identity" "[$APP_CONFIG_NAME] App Configuration store"

ensure_role_assignment "$PRINCIPAL_ID" "ServicePrincipal" "$KEY_VAULT_SECRETS_USER_ROLE" \
	"$KEY_VAULT_ID" "[$MANAGED_IDENTITY_NAME] managed identity" "[$KEY_VAULT_NAME] key vault"

#********************************************
# The cluster must be able to do workload identity
#********************************************

# Checked before installing anything, because the failure mode otherwise is silent and confusing: the
# extension installs and reports Succeeded, but the provider's controller pod never gets the mutating
# webhook that points its Entra authority at the right place, and every token exchange fails with an
# opaque authentication error at reconcile time instead of here.
echo "Checking that the [$AKS_CLUSTER_NAME] cluster has the OIDC issuer and Microsoft Entra Workload ID enabled..."
# `--output tsv` prints one value per line for a list of scalars, so the two flags are read into an
# array rather than split on a tab. An absent securityProfile leaves the second element unset, which the
# comparison below treats as disabled.
mapfile -t CLUSTER_FEATURES < <(az aks show \
	--name "$AKS_CLUSTER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "[oidcIssuerProfile.enabled, securityProfile.workloadIdentity.enabled]" \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ ${#CLUSTER_FEATURES[@]} == 0 ]]; then
	echo "Failed to read the [$AKS_CLUSTER_NAME] cluster in the [$RESOURCE_GROUP_NAME] resource group."
	echo "Create it first with the repository script:"
	echo "  ../../../scripts/01-user-assigned-managed-identity.sh"
	exit 1
fi

OIDC_ENABLED="${CLUSTER_FEATURES[0],,}"
WORKLOAD_IDENTITY_ENABLED="${CLUSTER_FEATURES[1],,}"

if [[ $OIDC_ENABLED != "true" || $WORKLOAD_IDENTITY_ENABLED != "true" ]]; then
	echo "The [$AKS_CLUSTER_NAME] cluster has oidcIssuerProfile.enabled=[$OIDC_ENABLED] and securityProfile.workloadIdentity.enabled=[$WORKLOAD_IDENTITY_ENABLED]."
	echo "Both must be true for the App Configuration Kubernetes Provider to authenticate. Recreate the cluster with:"
	echo "  az aks update --name $AKS_CLUSTER_NAME --resource-group $RESOURCE_GROUP_NAME --enable-oidc-issuer --enable-workload-identity"
	echo "or use the repository script ../../../scripts/01-user-assigned-managed-identity.sh, which enables both."
	exit 1
fi

echo "The [$AKS_CLUSTER_NAME] cluster has the OIDC issuer and Microsoft Entra Workload ID enabled"

#********************************************
# The Azure App Configuration AKS extension
#********************************************

echo "Making sure the [k8s-extension] Azure CLI extension is installed..."
az extension add --upgrade --name k8s-extension --only-show-errors 2>/dev/null

# Registering the resource provider is part of the documented quickstart. On the emulator the namespace is
# already registered and the call is a no-op; on a fresh Azure subscription it is required.
echo "Registering the [Microsoft.KubernetesConfiguration] resource provider..."
az provider register --namespace Microsoft.KubernetesConfiguration --only-show-errors 1>/dev/null

for _ in $(seq 1 30); do
	REGISTRATION_STATE=$(az provider show \
		--namespace Microsoft.KubernetesConfiguration \
		--query registrationState \
		--output tsv \
		--only-show-errors 2>/dev/null)
	[[ $REGISTRATION_STATE == "Registered" ]] && break
	echo "[Microsoft.KubernetesConfiguration] is [$REGISTRATION_STATE]: waiting..."
	sleep 10
done

if [[ $REGISTRATION_STATE != "Registered" ]]; then
	echo "The [Microsoft.KubernetesConfiguration] resource provider is [$REGISTRATION_STATE] instead of [Registered]"
	exit 1
fi

echo "Checking if the [$APP_CONFIG_EXTENSION_NAME] cluster extension actually exists on the [$AKS_CLUSTER_NAME] cluster..."
az k8s-extension show \
	--cluster-type managedClusters \
	--cluster-name "$AKS_CLUSTER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$APP_CONFIG_EXTENSION_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating the [$APP_CONFIG_EXTENSION_NAME] cluster extension on the [$AKS_CLUSTER_NAME] cluster..."

	# No --version and no --auto-upgrade-minor-version: the Azure CLI refuses --version unless the
	# auto-upgrade mode is `none`, and both Azure and the emulator install their current release. The
	# version actually installed is reported as currentVersion below.
	az k8s-extension create \
		--cluster-type managedClusters \
		--cluster-name "$AKS_CLUSTER_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$APP_CONFIG_EXTENSION_NAME" \
		--extension-type "$APP_CONFIG_EXTENSION_TYPE" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "The [$APP_CONFIG_EXTENSION_NAME] cluster extension was successfully created"
	else
		echo "Failed to create the [$APP_CONFIG_EXTENSION_NAME] cluster extension"
		exit 1
	fi
else
	echo "The [$APP_CONFIG_EXTENSION_NAME] cluster extension already exists on the [$AKS_CLUSTER_NAME] cluster"
fi

EXTENSION_STATE=$(az k8s-extension show \
	--cluster-type managedClusters \
	--cluster-name "$AKS_CLUSTER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$APP_CONFIG_EXTENSION_NAME" \
	--query provisioningState \
	--output tsv \
	--only-show-errors)

if [[ $EXTENSION_STATE != "Succeeded" ]]; then
	echo "The [$APP_CONFIG_EXTENSION_NAME] cluster extension is [$EXTENSION_STATE] instead of [Succeeded]"
	az k8s-extension show \
		--cluster-type managedClusters \
		--cluster-name "$AKS_CLUSTER_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$APP_CONFIG_EXTENSION_NAME" \
		--query "{state:provisioningState,statuses:statuses,error:errorInfo}" \
		--output json \
		--only-show-errors
	exit 1
fi

echo "The [$APP_CONFIG_EXTENSION_NAME] cluster extension is [Succeeded]"

# provisioningState alone is not proof that the controller is running, so wait for the rollout. This is
# also what catches an image pull failure, which is the most common way the install goes wrong.
echo "Waiting for the [$APP_CONFIG_PROVIDER_DEPLOYMENT] deployment in the [$APP_CONFIG_EXTENSION_NAMESPACE] namespace..."
if kubectl --namespace "$APP_CONFIG_EXTENSION_NAMESPACE" rollout status \
	"deployment/$APP_CONFIG_PROVIDER_DEPLOYMENT" --timeout=300s; then
	echo "The App Configuration Kubernetes Provider is running"
else
	echo "The App Configuration Kubernetes Provider did not become ready. Inspect it with:"
	echo "  kubectl -n $APP_CONFIG_EXTENSION_NAMESPACE get pods -o wide"
	echo "  kubectl -n $APP_CONFIG_EXTENSION_NAMESPACE describe deployment/$APP_CONFIG_PROVIDER_DEPLOYMENT"
	echo "  kubectl -n $APP_CONFIG_EXTENSION_NAMESPACE logs deployment/$APP_CONFIG_PROVIDER_DEPLOYMENT --tail=50"
	echo "If kubectl is not pointing at the cluster, run:"
	echo "  az aks get-credentials --name $AKS_CLUSTER_NAME --resource-group $RESOURCE_GROUP_NAME --overwrite-existing"
	exit 1
fi

echo "Checking that the [$APP_CONFIG_PROVIDER_CRD] custom resource definition is present..."
kubectl get crd "$APP_CONFIG_PROVIDER_CRD" --output name

if [[ $? != 0 ]]; then
	echo "The [$APP_CONFIG_PROVIDER_CRD] custom resource definition is missing: the extension did not install cleanly"
	exit 1
fi

#********************************************
# Summary
#********************************************

echo
echo "Key-values in the [$APP_CONFIG_NAME] App Configuration store:"
# --query rather than --fields: --fields makes the CLI request only the named fields from the service, so
# `value` comes back absent and the CLI then fails to render a Key Vault reference.
az appconfig kv list \
	--name "$APP_CONFIG_NAME" \
	--query "[].{Key:key,ContentType:contentType,Label:label}" \
	--output table \
	--only-show-errors

echo
echo "Secrets in the [$KEY_VAULT_NAME] key vault (names only, never values):"
az keyvault secret list \
	--vault-name "$KEY_VAULT_NAME" \
	--query "[].name" \
	--output tsv \
	--only-show-errors

echo
echo "The [$APP_CONFIG_EXTENSION_NAME] cluster extension:"
# az k8s-extension, not az resource list: the emulator excludes extensions from the generic resource listing.
az k8s-extension show \
	--cluster-type managedClusters \
	--cluster-name "$AKS_CLUSTER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$APP_CONFIG_EXTENSION_NAME" \
	--query "{name:name,type:extensionType,version:currentVersion,state:provisioningState,namespace:scope.cluster.releaseNamespace}" \
	--output json \
	--only-show-errors

echo
echo "Resources ready. Next: 02-build-docker-image.sh, 04-push-docker-image.sh, 05-deploy-app.sh"
