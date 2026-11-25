import os
import io
import logging
import datetime
from typing import List, Tuple
from azure.identity import DefaultAzureCredential, ClientSecretCredential
from azure.storage.blob import BlobServiceClient
from azure.core.exceptions import ResourceExistsError
from flask import Flask, flash, jsonify, render_template, request, redirect, url_for

# Initialize Flask application
app: Flask = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", os.urandom(24))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logging.getLogger("azure").setLevel(logging.WARNING)
logging.getLogger("urllib3").setLevel(logging.WARNING)
logger = logging.getLogger(__name__)

client_id: str | None
client_secret: str | None
tenant_id: str | None

connection_string: str | None = None
account_url: str | None = None
container_name: str | None = None
blob_service_client: BlobServiceClient | None = None

debug: bool = os.environ.get("FLASK_DEBUG", "false").lower() == "true"
activities: List[Tuple[str, str]] = []

# Suffix of the blobs holding the activities, one blob per activity.
ACTIVITY_BLOB_SUFFIX: str = "-activity.txt"

def is_activity_name(name: str | None) -> bool:
    """Whether the name is one of this app's activity blobs, and nothing else.

    Every activity is a blob called YYYY-MM-DD-HH-MM-SS-activity.txt, so requiring that shape is both the
    read filter and the write guard: it rejects an empty name and any name the app did not create. Names
    arrive from a form field, so they are checked before they reach the container.
    """
    return bool(name) and name == os.path.basename(str(name)) and str(name).endswith(ACTIVITY_BLOB_SUFFIX)

def get_environment_variables():
    """Get the value of an environment variable or raise an error if not set."""
    global connection_string, container_name, client_id, client_secret, tenant_id, account_url
    try:
        # Get Azure credentials from environment variables
        client_id = os.environ.get("AZURE_CLIENT_ID")
        client_secret = os.environ.get("AZURE_CLIENT_SECRET")
        tenant_id = os.environ.get("AZURE_TENANT_ID")

        # Get connection string from environment variable
        connection_string = os.environ.get("AZURE_STORAGE_ACCOUNT_CONNECTION_STRING")
        account_url = os.environ.get("AZURE_STORAGE_ACCOUNT_URL")

        # Get container name from environment variable with a default value
        container_name = os.environ.get("CONTAINER_NAME", "activities")
    except ValueError as ve:
        logger.error(f"Configuration Error: {ve}")
    except Exception as ex:
        logger.error(f"An error occurred: {ex}")

def get_blob_service_client():
    """Create a BlobServiceClient using the connection string."""
    global connection_string
    try:
        # Create BlobServiceClient
        logger.info(f"Creating BlobServiceClient...")

        if client_id and client_secret and tenant_id and account_url:
            # Use ClientSecretCredential for authentication
            logger.info("Using ClientSecretCredential with BlobServiceClient...")
            credential = ClientSecretCredential(tenant_id=tenant_id, 
                                                client_id=client_id, 
                                                client_secret=client_secret)
            blob_service_client = BlobServiceClient(account_url=account_url, credential=credential)
        elif connection_string:
            # Use connection string for authentication
            logger.info("Using storage account connection string with BlobServiceClient...")
            blob_service_client = BlobServiceClient.from_connection_string(connection_string)
        elif account_url:
            # Use DefaultAzureCredential for authentication
            logger.info("Using DefaultAzureCredential with BlobServiceClient...")
            credential = DefaultAzureCredential()
            blob_service_client = BlobServiceClient(account_url=account_url, credential=credential)
        else:
            raise ValueError("Insufficient configuration for BlobServiceClient. Please set the necessary environment variables.")
        
        logger.info("BlobServiceClient created successfully.")
        return blob_service_client
    except Exception as ex:
        logger.error(f"An error occurred while creating BlobServiceClient: {ex}")
        return None

def create_container_if_not_exists():
    """Create a container if it does not already exist."""
    global blob_service_client, container_name
    try:
        if not blob_service_client:
            raise ValueError("BlobServiceClient is not initialized. Please call get_blob_service_client() first.")

        # Create a ContainerClient
        if not container_name:
            raise ValueError("Container name is not set. Please set the CONTAINER_NAME environment variable.")

        # Get the container client
        logger.info(f"Creating container client for container: {container_name}")
        container_client = blob_service_client.get_container_client(container_name)

        # Check whether the container exists and create it if it does not
        if not container_client.exists():
            logger.info(f"Attempting to create container '{container_name}' if it does not exist.")
            container_client.create_container()
            logger.info(f"Container '{container_name}' created.")
        else:
            logger.info(f"Container '{container_name}' already exists.")
    except ValueError as ve:
        logger.error(f"Configuration Error: {ve}")
    except ResourceExistsError:
        logger.info(f"Container '{container_name}' already exists.")
    except Exception as ex:
        logger.error(f"An error occurred while creating the container: {ex}")

def read_blobs_from_container() -> bool:
    """Read all blobs from the container. Returns False when the read failed, which is logged."""
    global blob_service_client, container_name, activities
    try:
        if not blob_service_client:
            raise ValueError("BlobServiceClient is not initialized. Please call get_blob_service_client() first.")

        if not container_name:
            raise ValueError("Container name is not set. Please set the CONTAINER_NAME environment variable.")

        # Get the container client
        container_client = blob_service_client.get_container_client(container_name)

        # List all blobs in the container
        blob_list = container_client.list_blobs()

        for blob in blob_list:
            if blob.name:
                # Print blob details
                logger.info(f"Found blob: {blob.name} with size {blob.size} bytes")

                # Read blob content
                blob_client = container_client.get_blob_client(blob.name)
                blob_content = blob_client.download_blob().readall()
                if isinstance(blob_content, bytes):
                    blob_content = blob_content.decode('utf-8')
                else:
                    blob_content = str(blob_content)

                logger.info(f"Content of blob '{blob.name}': {blob_content}")
                activities.append((blob.name, blob_content))
        return True
    except ValueError as ve:
        logger.error(f"Configuration Error: {ve}")
    except Exception as ex:
        logger.error(f"An error occurred while reading blobs from the container: {ex}")
    return False

def create_blob_if_not_exists(name: str | None, content: str | None) -> bool:
    """Create a blob in the container if it does not already exist. Returns whether the blob is there."""
    global blob_service_client, container_name

    # Check if name and content are provided
    if not name or not content:
        raise ValueError("Both 'name' and 'content' must be provided to create a blob.")
    
    try:
        if not blob_service_client:
            raise ValueError("BlobServiceClient is not initialized. Please call get_blob_service_client() first.")

        if not container_name:
            raise ValueError("Container name is not set. Please set the CONTAINER_NAME environment variable.")

        # Get the container client
        container_client = blob_service_client.get_container_client(container_name)

        # Create a blob client
        blob_client = container_client.get_blob_client(name)

        # Check if the blob exists and create it if it does not
        logger.info(f"Creating blob '{name}' in container '{container_name}'.")
        with io.BytesIO(content.encode("utf-8")) as content_stream:
            blob_client.upload_blob(content_stream, blob_type="BlockBlob", overwrite=True)
        logger.info(f"Blob '{name}' created successfully.")
        return True
    except ValueError as ve:
        logger.error(f"Configuration Error: {ve}")
    except ResourceExistsError:
        logger.info(f"Blob '{name}' already exists in container '{container_name}'.")
        return True
    except Exception as ex:
        logger.error(f"An error occurred while creating the blob: {ex}")
    return False

def delete_blob(name: str) -> bool:
    """Delete a blob from the container. Returns whether the delete succeeded."""
    global blob_service_client, container_name
    try:
        if not blob_service_client:
            raise ValueError("BlobServiceClient is not initialized. Please call get_blob_service_client() first.")

        if not container_name:
            raise ValueError("Container name is not set. Please set the CONTAINER_NAME environment variable.")

        # Get the container client
        container_client = blob_service_client.get_container_client(container_name)

        # Create a blob client
        blob_client = container_client.get_blob_client(name)

        # Delete the blob
        logger.info(f"Deleting blob '{name}' from container '{container_name}'.")
        blob_client.delete_blob()
        logger.info(f"Blob '{name}' deleted successfully.")
        return True
    except ValueError as ve:
        logger.error(f"Configuration Error: {ve}")
    except Exception as ex:
        logger.error(f"An error occurred while deleting the blob: {ex}")
    return False

def update_blob(name: str, content: str) -> bool:
    """Update the content of an existing blob (overwrite in place). Returns whether the update succeeded."""
    global blob_service_client, container_name
    if not name or not content:
        raise ValueError("Both 'name' and 'content' must be provided.")
    try:
        if not blob_service_client:
            raise ValueError("BlobServiceClient is not initialized.")
        if not container_name:
            raise ValueError("Container name is not set.")
        container_client = blob_service_client.get_container_client(container_name)
        blob_client = container_client.get_blob_client(name)
        logger.info(f"Updating blob '{name}' in container '{container_name}'.")
        with io.BytesIO(content.encode("utf-8")) as content_stream:
            blob_client.upload_blob(content_stream, blob_type="BlockBlob", overwrite=True)
        logger.info(f"Blob '{name}' updated successfully.")
        return True
    except ValueError as ve:
        logger.error(f"Configuration Error: {ve}")
    except Exception as ex:
        logger.error(f"An error occurred while updating the blob: {ex}")
    return False

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        row_id = request.form.get('row_id', '').strip()
        activity = request.form.get('activity', '').strip()
        if activity:
            if row_id:
                # Update the existing blob content in place. The name comes from the form, so it is checked
                # before it reaches the container.
                if not is_activity_name(row_id):
                    logger.warning(f"Invalid activity name '{row_id}'.")
                    return redirect(url_for('index'))
                if update_blob(row_id, activity):
                    logger.info("Activity updated: %s (id %s)", activity, row_id)
                for i, act in enumerate(activities):
                    if act[0] == row_id:
                        activities[i] = (row_id, activity)
                        break
                flash('Activity updated successfully.')
            else:
                # Generate a unique blob name with a timestamp
                timestamp = datetime.datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
                name = f"{timestamp}{ACTIVITY_BLOB_SUFFIX}"
                if create_blob_if_not_exists(name, activity):
                    logger.info("Activity added: %s", activity)
                activities.append((name, activity))
                flash('Activity added successfully.')
        return redirect(url_for('index'))

    # Always reload activities from blob storage on GET
    activities.clear()
    if read_blobs_from_container():
        logger.info("Activity retrieved: %d activities", len(activities))
    return render_template('index.html', activities=activities)

@app.route('/delete/<string:activity_id>', methods=['POST'])
def delete(activity_id: str):
    """Delete the activity whose blob name is activity_id.

    The activity is identified by its blob name, never by its position in the rendered page: every replica
    reloads the container on each GET, so the list can change between rendering a page and submitting a
    delete from it, and a position would then delete whatever activity happens to sit there now.
    """
    if not is_activity_name(activity_id):
        logger.warning(f"Invalid activity name '{activity_id}'.")
        return redirect(url_for('index'))

    if delete_blob(activity_id):
        logger.info("Activity deleted: %s", activity_id)
    for i, act in enumerate(activities):
        if act[0] == activity_id:
            activities.pop(i)
            break
    flash('Activity deleted successfully.')
    return redirect(url_for('index'))

@app.route('/health')
def health():
    """Liveness and readiness probe: reports whether the blob container is reachable."""
    try:
        if not blob_service_client or not container_name:
            raise ValueError("BlobServiceClient is not initialized.")
        if not blob_service_client.get_container_client(container_name).exists():
            raise ValueError(f"Container '{container_name}' does not exist.")
        return jsonify({"status": "ok"})
    except Exception as ex:
        logger.warning(f"Health check failed: {ex}")
        return jsonify({"status": "unavailable"}), 503

# Initialize the application and Azure services when the module is loaded.
# This ensures that the setup runs regardless of how the app is started (e.g., via 'flask run' or directly).
get_environment_variables()
blob_service_client = get_blob_service_client()
if blob_service_client:
    # Create the container if it does not exist
    create_container_if_not_exists()

    # Read existing blobs from the container, if any
    read_blobs_from_container()

if __name__ == '__main__':
    app.run(debug=True)
