"""Azure Event Hubs producer for the KEDA tutorial.

Sends MESSAGE_COUNT events to the event hub and exits, so it can run as a Kubernetes Job. The
unprocessed events it leaves behind are what the KEDA azure-eventhub scaler observes to scale the
consumer Deployment out from zero.

Authentication uses the event hub's authorization rule connection string. Unlike the Service Bus
tutorial, where only the applications use a connection string and the scaler uses workload identity,
here the scaler uses one too: the azure-eventhub scaler reads the last enqueued sequence number over
AMQP, and the emulator's AMQP listener is plain TCP (its connection strings carry
UseDevelopmentEmulator=true), a mode that has no Microsoft Entra variant. See the tutorial README.
"""

import logging
import os
import sys

from azure.eventhub import EventData, EventHubProducerClient

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOG = logging.getLogger("producer")

# Events per send call. Batching keeps the Job short without hiding progress from the log, and 20
# small events stay far below the maximum size a single batch can hold.
SEND_BATCH_SIZE = 20


def required_environment_variable(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        LOG.error("The required environment variable [%s] is not set", name)
        sys.exit(1)
    return value


def main() -> None:
    connection_string = required_environment_variable("EVENTHUB_CONNECTION")
    eventhub_name = required_environment_variable("EVENTHUB_NAME")
    message_count = int(os.environ.get("MESSAGE_COUNT", "100"))

    LOG.info("Sending [%s] events to the [%s] event hub...", message_count, eventhub_name)

    # The connection string of a hub-level authorization rule already carries EntityPath, and the SDK
    # lets an explicit eventhub_name take precedence over it. Passing it keeps this script working
    # with a namespace-level rule too, whose connection string has no EntityPath.
    with EventHubProducerClient.from_connection_string(
        connection_string, eventhub_name=eventhub_name
    ) as producer:
        sent = 0
        while sent < message_count:
            batch_size = min(SEND_BATCH_SIZE, message_count - sent)

            # Events are distributed round-robin across the hub's partitions, because no partition key
            # and no partition id are set. Every partition therefore gets a backlog for the scaler.
            batch = producer.create_batch()
            for i in range(batch_size):
                batch.add(EventData(f"event-{sent + i}"))
            producer.send_batch(batch)

            sent += batch_size
            LOG.info("Sent [%s] of [%s] events", sent, message_count)
    LOG.info("Done: [%s] events are in the [%s] event hub", message_count, eventhub_name)


if __name__ == "__main__":
    main()
