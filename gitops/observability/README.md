# Production observability profile

The optional observability profile is bootstrapped by Terraform when
`enable_observability = true`. Terraform creates private, encrypted and
versioned S3 buckets for Loki and Tempo, dedicated IRSA roles, the
`observability` namespace and a generated Grafana admin Secret. Argo CD then
installs the following pinned Helm releases:

- kube-prometheus-stack: Prometheus Operator, Prometheus, Grafana,
  Alertmanager, kube-state-metrics and node-exporter.
- Loki: durable cluster logs in S3.
- Grafana Alloy: Kubernetes pod log collection and an OTLP receiver that
  forwards traces to Tempo.
- Tempo: durable distributed traces in S3.

The application Helm release receives an environment-specific `ServiceMonitor`
override from the Terraform bootstrap. This keeps the default local/demo path
free of monitoring CRDs while automatically scraping the API in the production
profile.

Grafana is intentionally a ClusterIP service and has no public Ingress by
default. Retrieve the generated admin password from the cluster and use a
temporary port-forward until an environment-specific authenticated ingress or
private access path has been configured:

```sh
kubectl -n observability get secret grafana-admin \
  -o jsonpath='{.data.admin-password}' | base64 --decode; echo
kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
```

The repository dashboard is loaded automatically by the Grafana sidecar. The
default alerts cover backend availability and readiness; connect Alertmanager
to an approved notification receiver before calling the environment fully
operational. Set `enable_alertmanager_notifications = true` to configure a
secret-backed webhook receiver. Create the Secret before bootstrap:

```sh
kubectl -n observability create secret generic alertmanager-webhook \
  --from-literal=webhook-url='https://example.invalid/alerts'
```
