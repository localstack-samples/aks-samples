"""The training job: receive one training request from the Service Bus queue with workload identity, read how many
seconds to train from it, and train a small PyTorch model on the GPU when PyTorch finds one, on the CPU otherwise.

KEDA's ScaledJob starts one Kubernetes Job for each message on the queue. The pod installs the Service Bus and identity
libraries into /tmp/pydeps when it starts (see scaledjob.yml), next to the PyTorch the image provides.
"""

import json
import os
import sys
import time

sys.path.insert(0, "/tmp/pydeps")

import torch  # noqa: E402
from azure.identity import DefaultAzureCredential  # noqa: E402
from azure.servicebus import ServiceBusClient, ServiceBusReceiveMode  # noqa: E402

train_seconds = int(os.environ["DEFAULT_TRAIN_SECONDS"])
# Empty on Azure. On the LocalStack emulator, the namespace's AMQP port isn't 443, so the client connects through a
# custom endpoint address, and the library then uses AMQP over WebSockets (websocket-client).
custom_endpoint = os.environ.get("SERVICE_BUS_CUSTOM_ENDPOINT") or None

# The message is deleted when it is received: a pod that loses its node, such as a Spot node Azure evicts, doesn't
# find it again, and the job's replacement pod trains for the default time.
with ServiceBusClient(
    os.environ["SERVICE_BUS_FULLY_QUALIFIED_NAMESPACE"],
    DefaultAzureCredential(),
    custom_endpoint_address=custom_endpoint,
) as client:
    with client.get_queue_receiver(
        os.environ["SERVICE_BUS_QUEUE_NAME"], receive_mode=ServiceBusReceiveMode.RECEIVE_AND_DELETE
    ) as receiver:
        messages = receiver.receive_messages(max_message_count=1, max_wait_time=30)
        if messages:
            body = json.loads(str(messages[0]))
            train_seconds = int(body.get("train_seconds", train_seconds))
            print(f"Received message {messages[0].message_id}: {body}", flush=True)
        else:
            print("No message in the queue: training for the default time", flush=True)

device = "cuda" if torch.cuda.is_available() else "cpu"
print(f"PyTorch {torch.__version__}, CUDA available: {torch.cuda.is_available()}", flush=True)
if device == "cuda":
    print(f"GPU: {torch.cuda.get_device_name(0)}", flush=True)

model = torch.nn.Linear(1024, 1024).to(device)
optimizer = torch.optim.SGD(model.parameters(), lr=0.01)
inputs = torch.randn(256, 1024, device=device)
targets = torch.randn(256, 1024, device=device)
started = time.monotonic()
next_report = started + 30
steps = 0
loss = torch.tensor(0.0)
while time.monotonic() - started < train_seconds:
    optimizer.zero_grad()
    loss = torch.nn.functional.mse_loss(model(inputs), targets)
    loss.backward()
    optimizer.step()
    steps += 1
    if time.monotonic() >= next_report:
        print(f"Step {steps}, loss {loss.item():.4f}", flush=True)
        next_report += 30
print(f"Trained {steps} steps on {device} in {train_seconds} seconds, final loss {loss.item():.4f}", flush=True)
