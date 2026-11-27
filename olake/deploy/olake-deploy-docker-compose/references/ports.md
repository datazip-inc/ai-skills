# Ports and access (docker compose)

## Published ports

| Service | Host port | URL | Started by |
| --- | --- | --- | --- |
| `olake-ui` | `8000` | `http://localhost:8000` (UI and API) | default |
| `temporal-ui` | `8081` | `http://localhost:8081` | `--profile debug` |
| `fusion` | `1630`, `1260`, `1261` | `http://localhost:1630` | `--profile fusion` |

Temporal (`7233`) and Postgres (`5432`) are not published; they are reachable only on the
`olake-network` compose network.

## Change a host port

Edit the left side of the mapping only:

```yaml
  olake-ui:
    ports:
      - "18000:8000"
```

Then `docker compose up -d` and open `http://localhost:18000`. Keep the container side (`8000`): other
services call `http://olake-ui:8000`.

Find what holds a port: `lsof -i :8000` (macOS, Linux).

## Reaching sources

The worker starts driver containers through the host's Docker daemon with no network set, so they run
on Docker's default `bridge` network, not on `olake-network`. In a driver container:

| Source runs on | `host` in the source config |
| --- | --- |
| The Docker host, Docker Desktop (macOS, Windows) | `host.docker.internal` |
| The Docker host, Linux | The host's IP on the bridge (often `172.17.0.1`) or LAN IP. The database must listen on it, not only on `127.0.0.1`. |
| Another container | Publish its port and use one of the above. A compose service name does not resolve. |
| A remote host or cloud service | Its host name. The Docker host needs outbound access to it. |

`localhost` in a source config is the driver container itself: `connection refused`.

The same applies to destinations: a MinIO or REST catalog started in another compose project is
reached through its published port on the host.

## Remote VM

To use the UI from another machine, open port `8000` in the VM firewall, or tunnel it:
`ssh -L 8000:localhost:8000 <USER>@<VM_HOST>`. The tunnel keeps the UI off the public network. Change
the admin password before you expose the port.
