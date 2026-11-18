# Volumes and data (docker compose)

TODO
- `./olake-data` bind mount at `/tmp/olake-config`: job configs, streams, state, logs.
- Named volumes: `temporal-postgresql-data`, `temporal-elasticsearch-data`.
- What `docker compose down -v` deletes; backup before upgrade or teardown.
