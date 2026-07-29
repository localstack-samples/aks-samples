"""Azure Service Bus producer for the KEDA tutorial.

Sends MESSAGE_COUNT messages to the queue and exits, so it can run as a Kubernetes Job. The
backlog it leaves behind is what the KEDA azure-servicebus scaler observes to scale the consumer
Deployment out from zero.

Authentication uses the namespace connection string: the emulator's Service Bus data plane speaks
plain-TCP AMQP (the connection string carries UseDevelopmentEmulator=true), a mode that has no
Microsoft Entra variant. The KEDA scaler itself authenticates with workload identity, because it
talks to the HTTPS management API instead. See the tutorial README.
"""

import logging
import os
import sys

from azure.servicebus import ServiceBusClient, ServiceBusMessage

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOG = logging.getLogger("producer")

# Messages per send call. Batching keeps the Job short without hiding progress from the log.
SEND_BATCH_SIZE = 20


def required_environment_variable(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        LOG.error("The required environment variable [%s] is not set", name)
        sys.exit(1)
    return value


def main() -> None:
    connection_string = required_environment_variable("SERVICEBUS_CONNECTION")
    queue_name = required_environment_variable("QUEUE_NAME")
    message_count = int(os.environ.get("MESSAGE_COUNT", "100"))

    LOG.info("Sending [%s] messages to the [%s] queue...", message_count, queue_name)
    with ServiceBusClient.from_connection_string(connection_string) as client:
        with client.get_queue_sender(queue_name=queue_name) as sender:
            sent = 0
            while sent < message_count:
                batch_size = min(SEND_BATCH_SIZE, message_count - sent)
                sender.send_messages(
                    [ServiceBusMessage(f"work-item-{sent + i}") for i in range(batch_size)]
                )
                sent += batch_size
                LOG.info("Sent [%s] of [%s] messages", sent, message_count)
    LOG.info("Done: [%s] messages are queued in [%s]", message_count, queue_name)


if __name__ == "__main__":
    main()
