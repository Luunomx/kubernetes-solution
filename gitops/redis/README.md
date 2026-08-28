# Optional Redis realtime backplane

The API uses process-local WebSockets by default, which is enough for the local demo and the default single-replica deployment. When the backend is scaled above one replica, provide a shared Redis instance and enable the wiring in the Helm values:

```yaml
backend:
  redis:
    enabled: true
    existingSecret: bulletinboard-redis
    connectionStringKey: connection-string
```

Create `bulletinboard-redis` through the cluster's secret manager. Its `connection-string` value should contain the Redis connection string, including authentication and TLS settings where supported. Managed Redis or an approved Redis operator is preferred for hosted environments; this repository intentionally does not install a single-node Redis instance automatically.
