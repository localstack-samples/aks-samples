"""Azure Service Bus consumer for the KEDA tutorial.

Receives messages in batches and simulates WORK_SECONDS of work per message before completing it,
so the queue drains slowly enough for the KEDA azure-servicebus scaler to observe the backlog and
for the HPA to scale this Deployment out from zero and back down to zero afterwards.

The Deployment starts at replicas: 0. Every running replica competes for the same queue, which is
the point of the sample: more replicas drain the backlog faster.
"""

import logging
import os
import signal
import sys
import time
from types import FrameType

from azure.servicebus import ServiceBusClient

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOG = logging.getLogger("consumer")

# Set to False by SIGTERM so an in-flight batch is completed before the pod exits, instead of
# leaving messages locked until their lock expires. Kubernetes sends SIGTERM on scale-in.
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

    connection_string = required_environment_variable("SERVICEBUS_CONNECTION")
    queue_name = required_environment_variable("QUEUE_NAME")
    work_seconds = float(os.environ.get("WORK_SECONDS", "2"))
    batch_size = int(os.environ.get("BATCH_SIZE", "5"))

    LOG.info(
        "Consuming from the [%s] queue in batches of [%s], [%s]s of work per message...",
        queue_name,
        batch_size,
        work_seconds,
    )
    processed = 0
    with ServiceBusClient.from_connection_string(connection_string) as client:
        with client.get_queue_receiver(queue_name=queue_name, max_wait_time=5) as receiver:
            while running:
                batch = receiver.receive_messages(max_message_count=batch_size, max_wait_time=5)
                if not batch:
                    LOG.info("The [%s] queue is empty, waiting...", queue_name)
                    time.sleep(work_seconds)
                    continue
                for message in batch:
                    if not running:
                        # Abandon the rest of the batch so another replica picks it up promptly.
                        receiver.abandon_message(message)
                        continue
                    time.sleep(work_seconds)
                    receiver.complete_message(message)
                    processed += 1
                    LOG.info("Processed message [%s]: %s", processed, str(message))
    LOG.info("Exiting after processing [%s] messages", processed)


if __name__ == "__main__":
    main()
