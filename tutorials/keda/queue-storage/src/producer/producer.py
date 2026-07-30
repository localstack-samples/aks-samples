"""Azure Storage Queue producer for the KEDA tutorial.

Sends MESSAGE_COUNT messages to the queue and exits, so it can run as a Kubernetes Job. The backlog
it leaves behind is what the KEDA azure-queue scaler observes to scale the consumer Deployment out
from zero.

Authentication uses Microsoft Entra Workload ID: DefaultAzureCredential picks up the projected
service account token that the workload-identity webhook injects into this pod, and exchanges it for
a Microsoft Entra token for the shared user-assigned managed identity, which holds the Storage Queue
Data Contributor role on the storage account. There is no connection string and no account key
anywhere in this tutorial. See the tutorial README.
"""

import logging
import os
import sys

from azure.identity import DefaultAzureCredential
from azure.storage.queue import QueueClient

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOG = logging.getLogger("producer")


def required_environment_variable(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        LOG.error("The required environment variable [%s] is not set", name)
        sys.exit(1)
    return value


def main() -> None:
    queue_endpoint = required_environment_variable("QUEUE_ENDPOINT")
    queue_name = required_environment_variable("QUEUE_NAME")
    message_count = int(os.environ.get("MESSAGE_COUNT", "100"))

    LOG.info(
        "Sending [%s] messages to the [%s] queue at [%s]...", message_count, queue_name, queue_endpoint
    )
    with QueueClient(
        account_url=queue_endpoint,
        queue_name=queue_name,
        credential=DefaultAzureCredential(),
    ) as queue_client:
        for i in range(message_count):
            queue_client.send_message(f"job-{i}")
            LOG.info("Sent [%s] of [%s] messages", i + 1, message_count)
    LOG.info("Done: [%s] messages are queued in [%s]", message_count, queue_name)


if __name__ == "__main__":
    main()
