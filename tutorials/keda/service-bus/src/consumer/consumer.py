"""Azure Service Bus consumer for the KEDA tutorial.

Receives messages in batches and simulates WORK_SECONDS of work per message before completing it,
so the queue drains slowly enough for the KEDA azure-servicebus scaler to observe the backlog and
for the HPA to scale this Deployment out from zero and back down to zero afterwards.

The Deployment starts at replicas: 0. Every running replica competes for the same queue, which is
the point of the sample: more replicas drain the backlog faster.

The loop is deliberately resilient, because a consumer that exits on a transient error is a broken
consumer. Service Bus gives at-least-once delivery: a message whose lock is lost, or whose AMQP link
drops before it is settled, is simply redelivered to some replica once the lock expires. So a failure
to settle one message is logged and the loop moves on, and a failure of the receiver itself is
recovered by reconnecting, instead of letting the pod crash. Crash-looping would otherwise burn the
queue's maxDeliveryCount and dead-letter the backlog rather than process it.
"""

import logging
import os
import signal
import sys
import time
from types import FrameType

from azure.servicebus import ServiceBusClient
from azure.servicebus.exceptions import ServiceBusError

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOG = logging.getLogger("consumer")

# Seconds to wait before reconnecting after the receiver itself failed.
RECONNECT_DELAY_SECONDS = 2

# Set to False by SIGTERM so an in-flight batch is finished before the pod exits, instead of
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


def process_batch(receiver, work_seconds: float, batch_size: int) -> int:
    """Process one batch of messages, returning how many were completed."""
    batch = receiver.receive_messages(max_message_count=batch_size, max_wait_time=5)
    if not batch:
        return 0

    completed = 0
    for message in batch:
        try:
            if not running:
                # Shutting down: hand the message back so another replica picks it up promptly.
                receiver.abandon_message(message)
                continue
            time.sleep(work_seconds)
            receiver.complete_message(message)
            completed += 1
            LOG.info("Processed message: %s", str(message))
        except ServiceBusError as error:
            # The lock expired or the link dropped before this message could be settled. Service Bus
            # will redeliver it, so the right move is to log and keep going.
            LOG.warning("Could not settle a message, it will be redelivered: %s", error)
    return completed


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
    while running:
        try:
            with ServiceBusClient.from_connection_string(connection_string) as client:
                with client.get_queue_receiver(queue_name=queue_name, max_wait_time=5) as receiver:
                    while running:
                        completed = process_batch(receiver, work_seconds, batch_size)
                        if completed:
                            processed += completed
                            LOG.info("Completed [%s] messages so far", processed)
                        else:
                            LOG.info("The [%s] queue is empty, waiting...", queue_name)
                            time.sleep(work_seconds)
        except ServiceBusError as error:
            if not running:
                break
            LOG.warning("The receiver failed, reconnecting: %s", error)
            time.sleep(RECONNECT_DELAY_SECONDS)

    LOG.info("Exiting after completing [%s] messages", processed)


if __name__ == "__main__":
    main()
