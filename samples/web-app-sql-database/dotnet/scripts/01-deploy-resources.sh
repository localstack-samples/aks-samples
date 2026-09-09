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

# Create the Azure SQL Server
echo "Checking if SQL server [$SQL_SERVER_NAME] exists..."
az sql server show \
	--name "$SQL_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating SQL server [$SQL_SERVER_NAME]..."
	az sql server create \
		--name "$SQL_SERVER_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--admin-user "$ADMIN_USER" \
		--admin-password "$ADMIN_PASSWORD" \
		--minimal-tls-version 1.2 \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "SQL server [$SQL_SERVER_NAME] created."
	else
		echo "Failed to create SQL server [$SQL_SERVER_NAME]."
		exit 1
	fi
else
	echo "SQL server [$SQL_SERVER_NAME] already exists."
fi

# Add a permissive firewall rule (dev/test only)
echo "Ensuring firewall rule [$FIREWALL_RULE_NAME] exists on SQL server [$SQL_SERVER_NAME]..."
az sql server firewall-rule create \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--server "$SQL_SERVER_NAME" \
	--name "$FIREWALL_RULE_NAME" \
	--start-ip-address 0.0.0.0 \
	--end-ip-address 255.255.255.255 \
	--only-show-errors 1>/dev/null

# Create the SQL Database
echo "Checking if SQL database [$SQL_DATABASE_NAME] exists..."
az sql db show \
	--name "$SQL_DATABASE_NAME" \
	--server "$SQL_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating SQL database [$SQL_DATABASE_NAME]..."
	az sql db create \
		--name "$SQL_DATABASE_NAME" \
		--server "$SQL_SERVER_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--service-objective S0 \
		--compute-model Provisioned \
		--zone-redundant false \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "SQL database [$SQL_DATABASE_NAME] created."
	else
		echo "Failed to create SQL database [$SQL_DATABASE_NAME]."
		exit 1
	fi
else
	echo "SQL database [$SQL_DATABASE_NAME] already exists."
fi

# Retrieve SQL Server FQDN
SQL_SERVER_FQDN=$(az sql server show \
	--name "$SQL_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "fullyQualifiedDomainName" \
	--output tsv)

if [ -z "$SQL_SERVER_FQDN" ]; then
	echo "Failed to retrieve SQL server FQDN."
	exit 1
fi
echo "SQL server FQDN: $SQL_SERVER_FQDN"

# Create a SQL login + database user + grant roles + create the Activities table.
# sqlcmd must be available on the host machine.
if ! command -v sqlcmd &>/dev/null; then
	echo "sqlcmd is not installed on the host. Install Microsoft sqlcmd tools (mssql-tools / go-sqlcmd) and re-run."
	exit 1
fi

echo "Creating SQL login [$DATABASE_USER_NAME] on server [$SQL_SERVER_FQDN]..."
sqlcmd -S "$SQL_SERVER_FQDN" \
	-U "$ADMIN_USER" \
	-P "$ADMIN_PASSWORD" \
	-d master \
	-Q "IF NOT EXISTS (SELECT name FROM sys.sql_logins WHERE name = '$DATABASE_USER_NAME') CREATE LOGIN [$DATABASE_USER_NAME] WITH PASSWORD = '$DATABASE_USER_PASSWORD';"

if [ $? -eq 0 ]; then
	echo "Login [$DATABASE_USER_NAME] created successfully"
else
	echo "Failed to create login [$DATABASE_USER_NAME]"
	exit 1
fi

echo "Creating database user [$DATABASE_USER_NAME] in database [$SQL_DATABASE_NAME]..."
sqlcmd -S "$SQL_SERVER_FQDN" \
	-U "$ADMIN_USER" \
	-P "$ADMIN_PASSWORD" \
	-d "$SQL_DATABASE_NAME" \
	-Q "IF NOT EXISTS (SELECT name FROM sys.database_principals WHERE name = '$DATABASE_USER_NAME') CREATE USER [$DATABASE_USER_NAME] FOR LOGIN [$DATABASE_USER_NAME];"

if [ $? -eq 0 ]; then
	echo "User [$DATABASE_USER_NAME] created successfully in database [$SQL_DATABASE_NAME]"
else
	echo "Failed to create user [$DATABASE_USER_NAME]"
	exit 1
fi

echo "Granting roles db_datareader, db_datawriter, db_ddladmin to [$DATABASE_USER_NAME]..."
sqlcmd -S "$SQL_SERVER_FQDN" \
	-U "$ADMIN_USER" \
	-P "$ADMIN_PASSWORD" \
	-d "$SQL_DATABASE_NAME" \
	-Q "ALTER ROLE db_datareader ADD MEMBER [$DATABASE_USER_NAME]; ALTER ROLE db_datawriter ADD MEMBER [$DATABASE_USER_NAME]; ALTER ROLE db_ddladmin ADD MEMBER [$DATABASE_USER_NAME];"

if [ $? -eq 0 ]; then
	echo "Permissions granted successfully to [$DATABASE_USER_NAME]"
else
	echo "Failed to grant permissions to [$DATABASE_USER_NAME]"
	exit 1
fi

echo "Creating table dbo.Activities in database [$SQL_DATABASE_NAME]..."
sqlcmd -S "$SQL_SERVER_FQDN" \
	-U "$ADMIN_USER" \
	-P "$ADMIN_PASSWORD" \
	-d "$SQL_DATABASE_NAME" \
	-Q "IF NOT EXISTS (SELECT * FROM sysobjects WHERE name = 'Activities' AND xtype = 'U') CREATE TABLE dbo.Activities (id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWSEQUENTIALID(), username VARCHAR(32) NOT NULL, activity VARCHAR(128) NOT NULL, timestamp DATETIME NOT NULL);"

if [ $? -eq 0 ]; then
	echo "Test [Activities] table created successfully"
else
	echo "Failed to create test [Activities] table"
	exit 1
fi

# Insert data
echo "Inserting test data into [Activities] table..."
sqlcmd -S "$SQL_SERVER_FQDN" \
	-d "$SQL_DATABASE_NAME" \
	-U "$DATABASE_USER_NAME" \
	-P "$DATABASE_USER_PASSWORD" \
  -N -C \
	-Q "IF NOT EXISTS (SELECT 1 FROM Activities)
			INSERT INTO Activities (username, activity, timestamp) 
			VALUES 
      ('paolo', 'Visit the Leaning Tower in Pisa', GETDATE()),
      ('paolo', 'Explore Etruscan walls in Volterra', GETDATE()),
      ('paolo', 'Climb Torre Grossa in San Gimignano', GETDATE()),
      ('paolo', 'Walk across Piazza del Campo in Siena', GETDATE()),
      ('paolo', 'Taste Brunello wine in Montalcino', GETDATE()),
      ('paolo', 'Sample Pecorino cheese in Pienza', GETDATE()),
      ('paolo', 'Admire Michelangelo''s David in Florence', GETDATE()),
      ('paolo', 'Relax by the beach in Viareggio', GETDATE()),
      ('paolo', 'Stroll along the Viareggio promenade', GETDATE());" \
	-V 1

if [ $? -eq 0 ]; then
	echo "Test data inserted successfully into [Activities] table"
else
	echo "Failed to insert test data into [Activities] table"
	exit 1
fi

# Query data
echo "Querying test data from [Activities] table..."
sqlcmd -S "$SQL_SERVER_FQDN" \
	-d "$SQL_DATABASE_NAME" \
	-U "$DATABASE_USER_NAME" \
	-P "$DATABASE_USER_PASSWORD" \
  -N -C \
	-Q "SELECT 
    		id, 
    		CAST(username AS VARCHAR(8)) AS username, 
    		CAST(activity AS VARCHAR(50)) AS activity, 
    		timestamp 
			FROM Activities;" \
	-V 1

if [ $? -eq 0 ]; then
	echo "Test data queried successfully from [Activities] table"
else
	echo "Failed to query test data from [Activities] table"
	exit 1
fi