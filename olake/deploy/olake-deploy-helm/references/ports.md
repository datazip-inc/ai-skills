# Ports and access (Helm)

## Services

| Service | Port | Type (default) | Value |
| --- | --- | --- | --- |
| `olake-ui` | `8000` (UI and API) | `ClusterIP` | `olakeUI.service.type`, `olakeUI.env.HTTP_PORT` |
| `temporal` | `7233` | `ClusterIP` | in-cluster only |
| `temporal-ui` | `8081` | — | `temporal.ui.enabled: true` |
| `postgresql` | `5432` | `ClusterIP` | in-cluster only |

## UI access

Port-forward, for one user or a test:

```bash
kubectl port-forward -n olake svc/olake-ui 8000:8000
```

Then `http://localhost:8000`. It stops when the command ends.

Ingress, for a shared URL:

```yaml
olakeUI:
  ingress:
    enabled: true
    className: "nginx"                 # nginx, traefik, alb ...
    annotations: {}
    hosts:
      - host: olake.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: olake-tls
        hosts:
          - olake.example.com
```

The cluster needs an ingress controller of that class. `helm status olake -n olake` prints the URL.
If uploads or long requests fail through the ingress, raise the controller's limits (for nginx:
`nginx.ingress.kubernetes.io/proxy-read-timeout`, `proxy-body-size`).

`LoadBalancer` or `NodePort`: set `olakeUI.service.type`. Put TLS in front, and change the admin
password before the UI is reachable from outside the cluster.

Temporal UI: `temporal.ui.enabled: true`, then
`kubectl port-forward -n olake svc/temporal-ui 8081:8081`. Keep it inside the cluster.

## What job pods need

Job pods run in the release namespace, on the pod network. They connect out to:

| Target | Port (typical) |
| --- | --- |
| Source database | `5432` Postgres, `3306` MySQL, `27017` MongoDB, `1433` MSSQL, `1521` Oracle, `50000` Db2 |
| Kafka brokers | `9092` / `9093` (every advertised broker address) |
| Iceberg catalog | REST `8181` or `443`, Hive metastore `9083`, JDBC catalog DB port, AWS Glue `443` |
| Object storage | S3, GCS, Azure `443`; MinIO `9000` |
| Shared storage (S3 mode) | The log bucket endpoint |
| Registry | `443`, for image pulls on the node |

Check from inside the namespace with a throwaway pod (removed on exit):

```bash
kubectl run -n olake nettest --rm -it --restart=Never --image=busybox:1.36 -- \
  nc -zv -w 5 <HOST> <PORT>
```

Common blocks: a `NetworkPolicy` with default deny on egress, a cloud security group or firewall that
does not allow the node or pod CIDR, and private DNS names the cluster cannot resolve. A database on
a developer laptop is not reachable from a cloud cluster.
