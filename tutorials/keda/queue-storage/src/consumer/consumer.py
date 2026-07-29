"""Azure Storage Queue consumer for the KEDA tutorial.

Receives messages in batches and simulates WORK_SECONDS of work per message before deleting it, so
the queue drains slowly enough for the KEDA azure-queue scaler to observe the backlog and for the HPA
to scale this Deployment out from zero and back down to zero afterwards.

Authentication uses Microsoft Entra Workload ID: DefaultAzureCredential picks up the projected
service account token that the workload-identity webhook injects into this pod, and exchanges it for
a Microsoft Entra token for the shared user-assigned managed identity, which holds the Storage Queue
Data Contributor role on the storage account. There is no connection string and no account key
anywhere in this tutorial. See the tutorial README.

The Deployment starts at replicas: 0. Every running replica competes for the same queue, which is the
point of the sample: more replicas drain the backlog faster. A received message is invisible to the
other replicas for VISIBILITY_TIMEOUT_SECONDS, which is what keeps them from processing it twice.
"""

import logging
import os
import signal
import sys
import time
from types import FrameType

from azure.identity import DefaultAzureCredential
from azure.storage.queue import QueueClient

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOG = logging.getLogger("consumer")

# How long a received message stays invisible to the other replicas. It must comfortably exceed
# BATCH_SIZE * WORK_SECONDS, otherwise a message becomes visible again while this replica is still
# working on it and a second replica picks it up.
VISIBILITY_TIMEOUT_SECONDS = 60

# Set to False by SIGTERM so an in-flight batch is finished before the pod exits, instead of leaving
# messages invisible until their visibility timeout expires. Kubernetes sends SIGTERM on scale-in.
running = True


def handle_sigterm(signum: int, frame: FrameType | None) -> None:
    global running
    LOG.info("SIGTERM received: finishing the current batch, then exiting")
    running = False


def required_environment_variable(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        LOG.error("The required environment variable [%s] is not set", name)
        sys.exit(1)
    return value


def main() -> None:
    signal.signal(signal.SIGTERM, handle_sigterm)

    queue_endpoint = required_environment_variable("QUEUE_ENDPOINT")
    queue_name = required_environment_variable("QUEUE_NAME")
    work_seconds = float(os.environ.get("WORK_SECONDS", "2"))
    batch_size = int(os.environ.get("BATCH_SIZE", "5"))

    LOG.info(
        "Consuming from the [%s] queue at [%s] in batches of [%s], [%s]s of work per message...",
        queue_name,
        queue_endpoint,
        batch_size,
        work_seconds,
    )
    processed = 0
    with QueueClient(
        account_url=queue_endpoint,
        queue_name=queue_name,
        credential=DefaultAzureCredential(),
    ) as queue_client:
        while running:
            received = 0
            for message in queue_client.receive_messages(
                messages_per_page=batch_size, visibility_timeout=VISIBILITY_TIMEOUT_SECONDS
            ):
                received += 1
                if not running:
                    # Make the message visible again so another replica picks it up promptly, instead
                    # of waiting out its visibility timeout.
                    queue_client.update_message(message, visibility_timeout=0)
                    continue
                time.sleep(work_seconds)
                queue_client.delete_message(message)
                processed += 1
                LOG.info("Processed message [%s]: %s", processed, message.content)
            if not received:
                LOG.info("The [%s] queue is empty, waiting...", queue_name)
                time.sleep(work_seconds)
    LOG.info("Exiting after processing [%s] messages", processed)


if __name__ == "__main__":
    main()
