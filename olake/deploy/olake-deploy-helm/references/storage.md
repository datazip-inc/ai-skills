# Storage (Helm)

TODO
- Default: in-cluster NFS server (`nfsServer.enabled: true`, 20Gi), shared ReadWriteMany volume for job files.
- Bring your own RWX StorageClass.
- S3 mode (`s3LogFileStorage`): in-cluster MinIO or external bucket.
- What survives `helm uninstall` (NFS components persist).
