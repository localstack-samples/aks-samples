"""Azure Event Hubs consumer for the KEDA tutorial.

Receives events from the event hub, simulates WORK_SECONDS of work per event, and checkpoints each
one to blob storage, so the hub drains slowly enough for the KEDA azure-eventhub scaler to observe
the lag and for the HPA to scale this Deployment out from zero and back down to zero afterwards.

Checkpointing is not optional here. Event Hubs is a log, not a queue: consumers never remove events,
they advance a cursor. The azure-eventhub scaler therefore computes the lag per partition as the last
enqueued sequence number minus the sequence number in the consumer group's checkpoint, which it reads
from the CHECKPOINT_CONTAINER blob container. A consumer that does not checkpoint leaves the reported
lag at its peak forever, and the Deployment never scales back to zero.

The Deployment starts at replicas: 0. Event Hubs assigns each partition to one consumer at a time, so
at most as many replicas as the hub has partitions receive events; the extra replicas the HPA creates
stay idle until a partition is released. That caps the useful parallelism at the partition count.
"""

import logging
import os
import signal
import sys
import time
from types import FrameType

from azure.eventhub import EventData, EventHubConsumerClient, PartitionContext
from azure.eventhub.extensions.checkpointstoreblob import BlobCheckpointStore

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOG = logging.getLogger("consumer")

# How long receive() waits on an idle partition before invoking the callback with event=None.
MAX_WAIT_SECONDS = 5

# Set to False by SIGTERM so no new work is started before the pod exits. Kubernetes sends SIGTERM on
# scale-in. The flag alone is not enough: receive() blocks until the client is closed, so the handler
# also closes the client, which is why it is held at module scope.
running = True
consumer_client: EventHubConsumerClient | None = None

# Work simulated per event and the number of events processed so far, read by the callback below.
work_seconds = 2.0
processed = 0


def handle_sigterm(signum: int, frame: FrameType | None) -> None:
    global running
    LOG.info("SIGTERM received: no new events will be processed, closing the consumer client")
    running = False
    if consumer_client is not None:
        # Closing the client is what returns from the blocking receive() call in main(). A checkpoint
        # that is in flight when the close lands may be skipped; that is harmless, because delivery is
        # at-least-once and the replica that takes the partition over resumes from the last
        # checkpoint, at worst reprocessing a single event.
        consumer_client.close()


def required_environment_variable(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        LOG.error("The required environment variable [%s] is not set", name)
        sys.exit(1)
    return value


def on_event(partition_context: PartitionContext, event: EventData | None) -> None:
    global processed

    if event is None:
        # No event arrived on this partition within max_wait_time: nothing to process, and nothing to
        # checkpoint either, because the cursor has not moved.
        LOG.info(
            "No events on partition [%s] for [%s]s, waiting...",
            partition_context.partition_id,
            MAX_WAIT_SECONDS,
        )
        return

    if not running:
        # Shutting down: leave the event uncheckpointed so another replica picks it up promptly.
        return

    time.sleep(work_seconds)

    # Advance the consumer group's cursor for this partition. This is the write the scaler reads to
    # compute the lag, so it has to happen for the Deployment to ever scale back to zero.
    partition_context.update_checkpoint(event)

    processed += 1
    LOG.info(
        "Processed event [%s] from partition [%s] with sequence number [%s]: %s",
        processed,
        partition_context.partition_id,
        event.sequence_number,
        event.body_as_str(),
    )


def main() -> None:
    global consumer_client, work_seconds

    signal.signal(signal.SIGTERM, handle_sigterm)

    eventhub_connection_string = required_environment_variable("EVENTHUB_CONNECTION")
    storage_connection_string = required_environment_variable("STORAGE_CONNECTION")
    eventhub_name = required_environment_variable("EVENTHUB_NAME")
    consumer_group = required_environment_variable("CONSUMER_GROUP")
    checkpoint_container = required_environment_variable("CHECKPOINT_CONTAINER")
    work_seconds = float(os.environ.get("WORK_SECONDS", "2"))

    # The container must already exist: the checkpoint store does not create it. It is created by
    # 03-create-resources.sh, before this Deployment is ever activated.
    checkpoint_store = BlobCheckpointStore.from_connection_string(
        storage_connection_string, checkpoint_container
    )

    LOG.info(
        "Consuming the [%s] event hub as consumer group [%s], checkpointing to the [%s] container, "
        "[%s]s of work per event...",
        eventhub_name,
        consumer_group,
        checkpoint_container,
        work_seconds,
    )
    consumer_client = EventHubConsumerClient.from_connection_string(
        eventhub_connection_string,
        consumer_group=consumer_group,
        eventhub_name=eventhub_name,
        checkpoint_store=checkpoint_store,
    )

    with consumer_client:
        # starting_position "-1" is the beginning of each partition, used only for a partition with no
        # checkpoint yet; a partition that has one resumes from it. receive() blocks until the client
        # is closed, which is what the SIGTERM handler does.
        consumer_client.receive(
            on_event=on_event,
            starting_position="-1",
            max_wait_time=MAX_WAIT_SECONDS,
        )
    LOG.info("Exiting after processing [%s] events", processed)


if __name__ == "__main__":
    main()
