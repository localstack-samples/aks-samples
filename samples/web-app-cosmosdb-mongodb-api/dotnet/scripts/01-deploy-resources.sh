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

# Create the Cosmos DB account (MongoDB API)
echo "Checking if Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group..."
az cosmosdb show \
	--name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] with MongoDB API..."
	az cosmosdb create \
		--name "$COSMOSDB_ACCOUNT_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--kind MongoDB \
		--server-version "$MONGODB_API_VERSION" \
		--default-consistency-level Session \
		--locations regionName="$LOCATION" \
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

# Make sure the account runs the MongoDB server version the sample asks for. The Azure CLI sends the
# --server-version of az cosmosdb create and az cosmosdb update as a ServerVersion property, which the service
# ignores, so the account keeps the default server version, 3.6, which the MongoDB drivers of the app and of
# mongosh refuse. The script sets the serverVersion property itself, with the API version the Azure CLI uses,
# and waits for the upgrade, which takes about a minute.
echo "Retrieving the MongoDB server version of Cosmos DB account [$COSMOSDB_ACCOUNT_NAME]..."
SERVER_VERSION=$(az cosmosdb show \
	--name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "apiProperties.serverVersion" \
	--output tsv \
	--only-show-errors)

if [[ -n $SERVER_VERSION ]]; then
	echo "Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] runs MongoDB server version [$SERVER_VERSION]"
else
	echo "Failed to retrieve the MongoDB server version of Cosmos DB account [$COSMOSDB_ACCOUNT_NAME]"
	exit 1
fi

if [[ "$SERVER_VERSION" != "$MONGODB_API_VERSION" ]]; then
	echo "Retrieving the resource id of Cosmos DB account [$COSMOSDB_ACCOUNT_NAME]..."
	COSMOSDB_ACCOUNT_ID=$(az cosmosdb show \
		--name "$COSMOSDB_ACCOUNT_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--query "id" \
		--output tsv \
		--only-show-errors)

	if [[ -n $COSMOSDB_ACCOUNT_ID ]]; then
		echo "Resource id of Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] retrieved successfully"
	else
		echo "Failed to retrieve the resource id of Cosmos DB account [$COSMOSDB_ACCOUNT_NAME]"
		exit 1
	fi

	echo "Upgrading Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] to MongoDB server version [$MONGODB_API_VERSION]..."
	az rest \
		--method patch \
		--url "${COSMOSDB_ACCOUNT_ID}?api-version=2026-03-15" \
		--body "{\"properties\": {\"apiProperties\": {\"serverVersion\": \"$MONGODB_API_VERSION\"}}}" \
		--only-show-errors 1>/dev/null

	if [[ $? != 0 ]]; then
		echo "Failed to upgrade Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] to MongoDB server version [$MONGODB_API_VERSION]"
		exit 1
	fi

	for ATTEMPT in $(seq 1 60); do
		SERVER_VERSION=$(az cosmosdb show \
			--name "$COSMOSDB_ACCOUNT_NAME" \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--query "apiProperties.serverVersion" \
			--output tsv \
			--only-show-errors)
		PROVISIONING_STATE=$(az cosmosdb show \
			--name "$COSMOSDB_ACCOUNT_NAME" \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--query "provisioningState" \
			--output tsv \
			--only-show-errors)

		if [[ "$SERVER_VERSION" == "$MONGODB_API_VERSION" && "$PROVISIONING_STATE" == "Succeeded" ]]; then
			break
		fi
		echo "Waiting for the upgrade of Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] (attempt $ATTEMPT of 60)..."
		sleep 10
	done

	if [[ "$SERVER_VERSION" == "$MONGODB_API_VERSION" && "$PROVISIONING_STATE" == "Succeeded" ]]; then
		echo "Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] successfully upgraded to MongoDB server version [$MONGODB_API_VERSION]"
	else
		echo "Failed to upgrade Cosmos DB account [$COSMOSDB_ACCOUNT_NAME]: it still runs MongoDB server version [$SERVER_VERSION]"
		exit 1
	fi
fi

# Create the MongoDB database
echo "Checking if MongoDB database [$COSMOSDB_DATABASE_NAME] exists in account [$COSMOSDB_ACCOUNT_NAME]..."
az cosmosdb mongodb database show \
	--account-name "$COSMOSDB_ACCOUNT_NAME" \
	--name "$COSMOSDB_DATABASE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating MongoDB database [$COSMOSDB_DATABASE_NAME]..."
	az cosmosdb mongodb database create \
		--account-name "$COSMOSDB_ACCOUNT_NAME" \
		--name "$COSMOSDB_DATABASE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "MongoDB database [$COSMOSDB_DATABASE_NAME] created successfully."
	else
		echo "Failed to create MongoDB database [$COSMOSDB_DATABASE_NAME]."
		exit 1
	fi
else
	echo "MongoDB database [$COSMOSDB_DATABASE_NAME] already exists in account [$COSMOSDB_ACCOUNT_NAME]"
fi

# Create the MongoDB collection
echo "Checking if MongoDB collection [$COSMOSDB_COLLECTION_NAME] exists in database [$COSMOSDB_DATABASE_NAME]..."
az cosmosdb mongodb collection show \
	--account-name "$COSMOSDB_ACCOUNT_NAME" \
	--database-name "$COSMOSDB_DATABASE_NAME" \
	--name "$COSMOSDB_COLLECTION_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating MongoDB collection [$COSMOSDB_COLLECTION_NAME]..."
	az cosmosdb mongodb collection create \
		--account-name "$COSMOSDB_ACCOUNT_NAME" \
		--database-name "$COSMOSDB_DATABASE_NAME" \
		--name "$COSMOSDB_COLLECTION_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--shard "$SHARD" \
		--throughput "$THROUGHPUT" \
		--idx "$INDEXES" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "MongoDB collection [$COSMOSDB_COLLECTION_NAME] created successfully."
	else
		echo "Failed to create MongoDB collection [$COSMOSDB_COLLECTION_NAME]."
		exit 1
	fi
else
	echo "MongoDB collection [$COSMOSDB_COLLECTION_NAME] already exists in database [$COSMOSDB_DATABASE_NAME]"
fi

# Retrieve the Cosmos DB MongoDB connection string
echo "Retrieving Cosmos DB MongoDB connection string for [$COSMOSDB_ACCOUNT_NAME]..."
COSMOSDB_CONNECTION_STRING=$(az cosmosdb keys list \
	--name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--type connection-strings \
	--query "connectionStrings[0].connectionString" \
	--output tsv)

if [ -n "$COSMOSDB_CONNECTION_STRING" ]; then
	echo "Cosmos DB connection string retrieved successfully."
else
	echo "Failed to retrieve Cosmos DB connection string."
	exit 1
fi

# Insert the sample activities, so the app does not start with an empty list. Each activity is a document
# {_id, username, activity, timestamp} of the user the app shows, the shape the app itself reads and writes; these
# are the activities the SQL Database, MySQL and PostgreSQL samples seed. A document id is the MD5 of the user and
# a fixed name, and each upsert sets the fields only when it creates the document, so a re-run inserts only the
# missing activities and leaves the others as they are. The filter of each upsert holds the shard key (username),
# which an update of a sharded collection requires.
# mongosh must be available on the host machine.
if ! command -v mongosh &>/dev/null; then
	echo "mongosh is not installed on the host. Install the MongoDB Shell (mongosh) and re-run."
	exit 1
fi

# After an upgrade, the MongoDB endpoint of the account can go on serving the old server version for several
# minutes after Azure Resource Manager reports the new one, and mongosh refuses a server older than 4.2. Wait until
# mongosh connects; each attempt that fails takes about 30 seconds, the time mongosh looks for a suitable server.
echo "Checking that the MongoDB endpoint of Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] accepts mongosh connections..."
MONGOSH_CONNECTED=false
for ATTEMPT in $(seq 1 30); do
	CONNECTION_ERROR=$(mongosh "$COSMOSDB_CONNECTION_STRING" --quiet --eval 'db.hello().ok' 2>&1 1>/dev/null)

	if [[ $? == 0 ]]; then
		MONGOSH_CONNECTED=true
		break
	fi
	echo "The MongoDB endpoint does not accept mongosh connections yet (attempt $ATTEMPT of 30): $CONNECTION_ERROR"
	sleep 10
done

if [[ $MONGOSH_CONNECTED == true ]]; then
	echo "The MongoDB endpoint of Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] accepts mongosh connections"
else
	echo "Failed to connect to the MongoDB endpoint of Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] with mongosh"
	exit 1
fi

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

# mongosh reads the values from its environment, so no activity needs quoting in the script
echo "Inserting the sample activities of [$LOGIN_NAME] into collection [$COSMOSDB_COLLECTION_NAME]..."
SEED_DATABASE="$COSMOSDB_DATABASE_NAME" \
	SEED_COLLECTION="$COSMOSDB_COLLECTION_NAME" \
	SEED_USERNAME="$LOGIN_NAME" \
	SEED_TIMESTAMP="$(date '+%Y-%m-%dT%H:%M:%S.000000')" \
	SEED_ACTIVITIES="$(printf '%s\n' "${SAMPLE_ACTIVITIES[@]}")" \
	mongosh "$COSMOSDB_CONNECTION_STRING" --quiet --eval '
		const crypto = require("crypto");
		const env = process.env;
		const collection = db.getSiblingDB(env.SEED_DATABASE).getCollection(env.SEED_COLLECTION);
		const operations = env.SEED_ACTIVITIES.trim().split("\n").map((line) => {
			const separator = line.indexOf("|");
			const name = line.slice(0, separator);
			const activity = line.slice(separator + 1);
			const id = crypto.createHash("md5").update(`${env.SEED_USERNAME}_${name}_seed`).digest("hex");
			return {
				updateOne: {
					filter: { _id: id, username: env.SEED_USERNAME },
					update: { $setOnInsert: { activity: activity, timestamp: env.SEED_TIMESTAMP } },
					upsert: true
				}
			};
		});
		const result = collection.bulkWrite(operations, { ordered: false });
		print(`${result.upsertedCount} activities inserted, ${result.matchedCount} already present`);
	'

if [ $? -eq 0 ]; then
	echo "Sample activities inserted successfully into collection [$COSMOSDB_COLLECTION_NAME]."
else
	echo "Failed to insert the sample activities into collection [$COSMOSDB_COLLECTION_NAME]."
	exit 1
fi

# Query the activities of the user back
echo "Querying the activities of [$LOGIN_NAME] from collection [$COSMOSDB_COLLECTION_NAME]..."
SEED_DATABASE="$COSMOSDB_DATABASE_NAME" \
	SEED_COLLECTION="$COSMOSDB_COLLECTION_NAME" \
	SEED_USERNAME="$LOGIN_NAME" \
	mongosh "$COSMOSDB_CONNECTION_STRING" --quiet --eval '
		const env = process.env;
		db.getSiblingDB(env.SEED_DATABASE)
			.getCollection(env.SEED_COLLECTION)
			.find({ username: env.SEED_USERNAME }, { _id: 0, activity: 1 })
			.forEach((document) => print(`  - ${document.activity}`));
	'

if [ $? -eq 0 ]; then
	echo "Activities of [$LOGIN_NAME] queried successfully."
else
	echo "Failed to query the activities of [$LOGIN_NAME]."
	exit 1
fi

export COSMOSDB_CONNECTION_STRING
