---
name: olake-driver-kafka
description: "Read Kafka topics into OLake (self-hosted, Confluent, MSK): source.json, bootstrap servers, SASL and SSL, consumer group, topic pattern, JSON or Avro with Schema Registry. Use when the source is Kafka, or on broker, auth or offset errors."
metadata:
  parent: olake-driver-abstract
  status: experimental
---

# Kafka source

Image: `olakego/source-kafka:<tag>`. Each topic is one stream. Sync mode: `strict_cdc` only (reads new
messages from the consumer group's position). The run (`check`, `discover`, `sync`) is in `olake-protocol`.

## When to use

- The source is Kafka: self-hosted, Confluent Cloud, Amazon MSK.
- `check` fails on the brokers.

## Inputs to collect

Ask only for what is missing. Never echo a password or key back.

| Input | Example | Where it comes from |
| --- | --- | --- |
| `bootstrap_servers` | `broker-1:9092,broker-2:9092` | User. From a container, `localhost` is the container: use `host.docker.internal` or the Docker network service name. |
| `protocol.security_protocol` | `PLAINTEXT`, `SASL_SSL` | User |
| `protocol.sasl_mechanism`, `protocol.sasl_jaas_config` | `PLAIN`, `<JAAS_CONFIG>` | User, SASL only |
| `consumer_group_id` | `olake-orders` | User. Empty: OLake creates `olake-consumer-group-<timestamp>` and keeps it in `state.json`. |
| `topic_pattern` | `^orders.*` | User. Regex of topics to discover. |
| Avro with Schema Registry? | yes / no | User. Yes: `"use_schema_registry": true` and `schema_registry`. |

## Prerequisites

- [ ] The user or SASL principal can describe and read the topics, and use the consumer group.
- [ ] Messages are JSON, or Avro with a reachable Schema Registry.

## Steps

1. Write `source.json` in the config folder (example below). Every field:
   [references/config.md](references/config.md).
2. `check` the source, then `discover` (`olake-protocol` steps 2 to 4).
3. In `selected_streams.json`, set the sync mode per stream.
4. Sync, then rerun with `--state` (`olake-protocol` steps 6 and 7).

```json
{
  "bootstrap_servers": "<BOOTSTRAP_SERVERS>",
  "protocol": { "security_protocol": "PLAINTEXT" },
  "consumer_group_id": "<CONSUMER_GROUP_ID>",
  "topic_pattern": "<TOPIC_REGEX>",
  "max_threads": 3
}
```

SASL_SSL (Confluent Cloud, MSK with SASL/SCRAM):
`"protocol": { "security_protocol": "SASL_SSL", "sasl_mechanism": "PLAIN", "sasl_jaas_config": "<JAAS_CONFIG>" }`.

## Verify

- `check` prints `"status":"SUCCEEDED"`.
- Each topic is a table on the destination; its row count equals the records in `stats.json`.
- Produce a message, rerun with `--state`, and find it on the destination.

## Common errors

| Error | Cause | Fix |
| --- | --- | --- |
| `consumer_group_id mismatch (destination metadata=..., current=...)` | `consumer_group_id` changed after the first sync | Restore the old ID, or `clear-destination` and re-sync. |
| `... broker committed offset ... is ahead of destination metadata offset` | Group offsets moved outside OLake | `clear-destination` for the stream, then sync. |
| `failed to fetch schema for topic <topic>` | Schema Registry not reachable or wrong credentials | Check the registry URL from inside the container. |
| `bootstrap_servers is required` | Missing field | Set `bootstrap_servers`; every advertised broker must be reachable. |

## Next

- The run, reruns and state: `olake-protocol`.
- Sync modes in general: `olake-driver-abstract`.
- Destination setup: `olake-destination-abstract`, then the destination skill.

## Rules

- Always rerun with `--state`: it holds the consumer group id. Without it, a new group starts.
- Never share a consumer group between two OLake jobs.
- Use `<JAAS_CONFIG>` placeholders; never print secrets.
