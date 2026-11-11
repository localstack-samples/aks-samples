#!/bin/bash

# Variables
source ./00-variables.sh

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Create a resource group
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]..."
az group show --name $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]"
	echo "Creating resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]..."

	az group create \
		--name $RESOURCE_GROUP_NAME \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "Resource group [$RESOURCE_GROUP_NAME] successfully created in the subscription [$SUBSCRIPTION_NAME]"
	else
		echo "Failed to create resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]"
		exit 1
	fi
else
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists in the subscription [$SUBSCRIPTION_NAME]"
fi

# Create the Azure Container Registry
echo "Checking if [$ACR_NAME] Azure Container Registry already exists in the [$RESOURCE_GROUP_NAME] resource group..."
az acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$ACR_NAME] Azure Container Registry exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating Azure Container Registry [$ACR_NAME]..."
	az acr create \
		--name "$ACR_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--sku "$ACR_SKU" \
		--admin-enabled true \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Azure Container Registry [$ACR_NAME] created successfully."
	else
		echo "Failed to create Azure Container Registry [$ACR_NAME]."
		exit 1
	fi
else
	echo "[$ACR_NAME] Azure Container Registry already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Create the Cosmos DB account (NoSQL / SQL API - default kind GlobalDocumentDB)
echo "Checking if Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group..."
az cosmosdb show \
	--name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] with NoSQL API..."
	az cosmosdb create \
		--name "$COSMOSDB_ACCOUNT_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--locations regionName="$LOCATION" \
		--default-consistency-level Session \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] created successfully."
	else
		echo "Failed to create Cosmos DB account [$COSMOSDB_ACCOUNT_NAME]."
		exit 1
	fi
else
	echo "Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Retrieve the document endpoint
echo "Retrieving document endpoint for Cosmos DB account [$COSMOSDB_ACCOUNT_NAME]..."
AZURECOSMOSDB_ENDPOINT=$(az cosmosdb show \
	--name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "documentEndpoint" \
	--output tsv)

if [ -n "$AZURECOSMOSDB_ENDPOINT" ]; then
	echo "Document endpoint retrieved successfully: $AZURECOSMOSDB_ENDPOINT"
else
	echo "Failed to retrieve document endpoint."
	exit 1
fi

# Create the SQL database
echo "Checking if SQL database [$AZURECOSMOSDB_DATABASENAME] exists in account [$COSMOSDB_ACCOUNT_NAME]..."
az cosmosdb sql database show \
	--account-name "$COSMOSDB_ACCOUNT_NAME" \
	--name "$AZURECOSMOSDB_DATABASENAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating SQL database [$AZURECOSMOSDB_DATABASENAME]..."
	az cosmosdb sql database create \
		--account-name "$COSMOSDB_ACCOUNT_NAME" \
		--name "$AZURECOSMOSDB_DATABASENAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "SQL database [$AZURECOSMOSDB_DATABASENAME] created successfully."
	else
		echo "Failed to create SQL database [$AZURECOSMOSDB_DATABASENAME]."
		exit 1
	fi
else
	echo "SQL database [$AZURECOSMOSDB_DATABASENAME] already exists in account [$COSMOSDB_ACCOUNT_NAME]"
fi

# Create the SQL container
echo "Checking if SQL container [$AZURECOSMOSDB_CONTAINERNAME] exists in database [$AZURECOSMOSDB_DATABASENAME]..."
az cosmosdb sql container show \
	--account-name "$COSMOSDB_ACCOUNT_NAME" \
	--database-name "$AZURECOSMOSDB_DATABASENAME" \
	--name "$AZURECOSMOSDB_CONTAINERNAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating SQL container [$AZURECOSMOSDB_CONTAINERNAME]..."
	az cosmosdb sql container create \
		--account-name "$COSMOSDB_ACCOUNT_NAME" \
		--database-name "$AZURECOSMOSDB_DATABASENAME" \
		--name "$AZURECOSMOSDB_CONTAINERNAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--partition-key-path "$AZURECOSMOSDB_PARTITION_KEY" \
		--throughput "$THROUGHPUT" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "SQL container [$AZURECOSMOSDB_CONTAINERNAME] created successfully."
	else
		echo "Failed to create SQL container [$AZURECOSMOSDB_CONTAINERNAME]."
		exit 1
	fi
else
	echo "SQL container [$AZURECOSMOSDB_CONTAINERNAME] already exists in database [$AZURECOSMOSDB_DATABASENAME]"
fi

# Retrieve the primary master key
echo "Retrieving primary master key for Cosmos DB account [$COSMOSDB_ACCOUNT_NAME]..."
AZURECOSMOSDB_PRIMARY_KEY=$(az cosmosdb keys list \
	--name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "primaryMasterKey" \
	--output tsv)

if [ -n "$AZURECOSMOSDB_PRIMARY_KEY" ]; then
	echo "Primary master key retrieved successfully."
else
	echo "Failed to retrieve primary master key."
	exit 1
fi

# Insert the sample activities, so the app does not start with an empty list. Each activity is an item
# {id, username, activity, timestamp} of the user the app shows, the shape the app itself reads and writes; these
# are the activities the SQL Database, MySQL and PostgreSQL samples seed. The Azure CLI has no command for items,
# so the script calls the Cosmos DB REST API with curl and signs each request with the primary master key. An
# item id is the MD5 of the user and a fixed name, so a re-run inserts only the missing activities: Cosmos DB
# answers 409 Conflict for an id that already exists.
# curl and openssl must be available on the host machine.
for TOOL in curl openssl; do
	if ! command -v $TOOL &>/dev/null; then
		echo "$TOOL is not installed on the host. Install it and re-run."
		exit 1
	fi
done

lowercase() {
	echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Print the Authorization header of a Cosmos DB REST request, signed with the primary master key as described in
# https://learn.microsoft.com/rest/api/cosmos-db/access-control-on-cosmosdb-resources
cosmosdb_authorization() {
	local verb=$1
	local resource_type=$2
	local resource_link=$3
	local request_date=$4
	local key_hex
	local signature

	key_hex=$(printf '%s' "$AZURECOSMOSDB_PRIMARY_KEY" | openssl base64 -d -A | od -An -v -tx1 | tr -d ' \n')
	signature=$(printf '%s\n%s\n%s\n%s\n\n' \
		"$(lowercase "$verb")" \
		"$(lowercase "$resource_type")" \
		"$resource_link" \
		"$(lowercase "$request_date")" |
		openssl dgst -sha256 -mac HMAC -macopt "hexkey:$key_hex" -binary |
		openssl base64 -A |
		sed -e 's/+/%2B/g' -e 's/\//%2F/g' -e 's/=/%3D/g')
	echo "type%3Dmaster%26ver%3D1.0%26sig%3D$signature"
}

SAMPLE_ACTIVITIES=(
	"pisa|Visit the Leaning Tower in Pisa"
	"volterra|Explore Etruscan walls in Volterra"
	"san_gimignano|Climb Torre Grossa in San Gimignano"
	"siena|Walk across Piazza del Campo in Siena"
	"montalcino|Taste Brunello wine in Montalcino"
	"pienza|Sample Pecorino cheese in Pienza"
	"florence|Admire Michelangelo's David in Florence"
	"viareggio_beach|Relax by the beach in Viareggio"
	"viareggio_promenade|Stroll along the Viareggio promenade"
)
DOCUMENTS_LINK="dbs/$AZURECOSMOSDB_DATABASENAME/colls/$AZURECOSMOSDB_CONTAINERNAME"
DOCUMENTS_URL="${AZURECOSMOSDB_ENDPOINT%/}/$DOCUMENTS_LINK/docs"
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S.000000')

for SAMPLE_ACTIVITY in "${SAMPLE_ACTIVITIES[@]}"; do
	SAMPLE_NAME="${SAMPLE_ACTIVITY%%|*}"
	ACTIVITY="${SAMPLE_ACTIVITY#*|}"
	ITEM_ID=$(printf '%s' "${LOGIN_NAME}_${SAMPLE_NAME}_seed" | openssl dgst -md5 | sed 's/^.*= //')
	REQUEST_DATE=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S GMT')

	# The response body is kept only to print it on failure; the last line of the output is the HTTP status
	echo "Inserting sample activity [$ACTIVITY] as item [$ITEM_ID] into container [$AZURECOSMOSDB_CONTAINERNAME]..."
	RESPONSE=$(curl --silent --show-error \
		--request POST "$DOCUMENTS_URL" \
		--header "Authorization: $(cosmosdb_authorization POST docs "$DOCUMENTS_LINK" "$REQUEST_DATE")" \
		--header "x-ms-date: $REQUEST_DATE" \
		--header "x-ms-version: 2018-12-31" \
		--header "x-ms-documentdb-partitionkey: [\"$LOGIN_NAME\"]" \
		--header "Content-Type: application/json" \
		--data "{\"id\": \"$ITEM_ID\", \"username\": \"$LOGIN_NAME\", \"activity\": \"$ACTIVITY\", \"timestamp\": \"$TIMESTAMP\"}" \
		--write-out '\n%{http_code}')
	STATUS_CODE="${RESPONSE##*$'\n'}"

	if [[ $STATUS_CODE == 201 ]]; then
		echo "Item [$ITEM_ID] inserted successfully."
	elif [[ $STATUS_CODE == 409 ]]; then
		echo "Item [$ITEM_ID] already exists."
	else
		echo "Failed to insert item [$ITEM_ID]: HTTP status [$STATUS_CODE] ${RESPONSE%$'\n'*}"
		exit 1
	fi
done

# Query the activities of the user back
echo "Querying the activities of [$LOGIN_NAME] from container [$AZURECOSMOSDB_CONTAINERNAME]..."
REQUEST_DATE=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S GMT')
RESPONSE=$(curl --silent --show-error \
	--request POST "$DOCUMENTS_URL" \
	--header "Authorization: $(cosmosdb_authorization POST docs "$DOCUMENTS_LINK" "$REQUEST_DATE")" \
	--header "x-ms-date: $REQUEST_DATE" \
	--header "x-ms-version: 2018-12-31" \
	--header "x-ms-documentdb-isquery: True" \
	--header "x-ms-documentdb-partitionkey: [\"$LOGIN_NAME\"]" \
	--header "Content-Type: application/query+json" \
	--data "{\"query\": \"SELECT c.id, c.activity FROM c WHERE c.username = @username\", \"parameters\": [{\"name\": \"@username\", \"value\": \"$LOGIN_NAME\"}]}" \
	--write-out '\n%{http_code}')
STATUS_CODE="${RESPONSE##*$'\n'}"

if [[ $STATUS_CODE == 200 ]]; then
	echo "Activities of [$LOGIN_NAME] queried successfully:"
	grep -o '"activity": *"[^"]*"' <<<"${RESPONSE%$'\n'*}" | sed -e 's/^"activity": *"/  - /' -e 's/"$//'
else
	echo "Failed to query the activities of [$LOGIN_NAME]: HTTP status [$STATUS_CODE] ${RESPONSE%$'\n'*}"
	exit 1
fi

export AZURECOSMOSDB_ENDPOINT
export AZURECOSMOSDB_PRIMARY_KEY
