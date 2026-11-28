# 0011: The smoke suite loads from a local fixture server

Status: accepted

## Context

The smoke suite used to load from six third-party hosts. A slow or changed
host looked like a product bug, and a public host cannot answer by request
header, send chosen `Cache-Control`, send slowly on purpose or say how many
requests arrived.

## Decision

`scripts/fixture-server.py` (Python standard library) serves committed
fixtures over loopback HTTP. The simulator shares the host's loopback; the
emulator reaches it through `adb reverse`.

## Consequences

- Deterministic, and scenarios can assert what the server received.
- The suite makes no HTTPS request, so a regression in how the adapters configure TLS would go unseen.
- The Android example must allow cleartext to `localhost`.

More: RFC §8.
