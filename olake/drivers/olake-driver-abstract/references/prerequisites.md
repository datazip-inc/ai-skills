# CDC prerequisites check

Source: [`drivers/abstract/prerequisites.go`](https://github.com/datazip-inc/olake-go/blob/master/drivers/abstract/prerequisites.go).

Drivers with CDC run a set of checks on the source during `check` and `sync` setup (each check times out
after 30 seconds). The results are in the `prerequisites` list of the `check` output, sorted: required
failures first, then optional failures, then passed checks.

```json
{
  "name": "wal_level",
  "required": true,
  "passed": false,
  "current_value": "replica",
  "recommended_value": "logical",
  "description": "..."
}
```

| Field | Meaning |
| --- | --- |
| `required` | `true`: CDC cannot work without it. `false`: recommended only. |
| `passed` | Whether the current value is acceptable. |
| `current_value` | Value read from the source, or `unavailable` when the check could not run. |
| `recommended_value` | What to set. |
| `error` | Why the check could not run (grants, network, timeout). |

## How to act

1. Fix every entry with `"required": true, "passed": false`. With CDC configured, `check` fails until
   they pass: `required CDC prerequisites not met: <names>`.
2. An entry with `current_value: "unavailable"` means the user lacks rights to read the setting, or the
   source did not answer. Fix that before changing the setting.
3. Optional failures (`"required": false`) do not stop the sync. Tell the user, and let them decide.
4. Run `check` again until no required check fails.

The settings to change, per source: [driver-setup.md](driver-setup.md).
