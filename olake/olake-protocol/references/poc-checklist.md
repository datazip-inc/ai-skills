# POC checklist

Go through it in order. Stop and fix at the first unchecked item.

- [ ] Goal agreed: source, tables, destination, catalog, storage, query engine that will read the data.
- [ ] Combination is in `compatibility-matrix.md`, or the user accepts going without a skill for part of it.
- [ ] Docker running: `docker info` succeeds.
- [ ] Network: source, catalog and storage reachable from the containers.
- [ ] Source prerequisites done (driver skill), especially for `cdc` and `strict_cdc`.
- [ ] Source `check` succeeded, with every required prerequisite passed.
- [ ] Destination `check` succeeded.
- [ ] `discover` listed the expected streams.
- [ ] Streams and sync modes set in `selected_streams.json`.
- [ ] First sync finished; `stats.json` shows synced records.
- [ ] Row counts match between source and destination.
- [ ] For `incremental` / `cdc`: one change in the source, rerun with `--state`, change visible in the destination.
- [ ] Data readable from the user's query engine.
