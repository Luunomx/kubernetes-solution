# Production-readiness audit

**Audit date:** 2026-08-28  
**Scope:** application code, local runtime, containers, CI/CD, Terraform, EKS bootstrap, GitOps/Helm, data protection, observability and operational controls.

## Executive verdict

This repository is now a strong **production-minded Kubernetes reference/template**. The delivery chain is coherent: a push can test, build, scan, sign and publish the images; an approved provisioning run can create or update EKS, bootstrap Argo CD and reconcile the application; and the optional observability profile adds metrics, logs, traces, dashboards and baseline alerts.

It is **not yet a production-grade public message board** without environment-specific hardening. The application is intentionally anonymous and has no identity, authorization or moderation model. TLS, shared realtime infrastructure, backups, notifications and observability are configurable profiles rather than universal defaults. That is appropriate for a template, but each profile must be enabled and configured before an internet-facing launch.

No live AWS account or EKS cluster was available during this audit. The conclusions below are therefore based on static inspection and local render/tests; they are not a substitute for a staged deployment, load test, restore exercise and security review.

## What is implemented

### Application and local development

- ASP.NET Core 8 API with health endpoints, rate limiting, input validation and Prometheus-compatible metrics.
- React/Vite frontend with REST and WebSocket updates.
- In-memory storage for the local demo and MongoDB storage for persistent deployments.
- Optional Redis Pub/Sub backplane for WebSocket fan-out when the backend is scaled beyond one replica.
- Docker Compose path with persistent MongoDB.
- MongoDB post IDs use an atomic counter seeded from existing data, so concurrent API replicas do not use the previous read-then-increment path.

### Delivery and infrastructure

- GitHub Actions frontend lint/build and .NET tests on the image workflow.
- GHCR images tagged by commit SHA, SBOM/provenance generation, Trivy HIGH/CRITICAL scanning and keyless cosign signing.
- GitOps promotion through Argo CD and Helm.
- One-trigger, manually dispatched EKS workflow with GitHub OIDC, Terraform state bootstrap, production-environment approval and idempotent apply.
- Terraform VPC, private EKS node subnets, EBS CSI, IRSA, External Secrets and optional cert-manager TLS.
- Optional EKS KMS Secrets encryption, control-plane logs, restricted API endpoint CIDRs and API-based EKS Access Entries.
- Production bootstrap guardrails: non-root workloads, frontend HPA/PDB, ResourceQuota/LimitRange and Pod Security audit/warn labels.
- MongoDB Community Operator with optional encrypted/versioned S3 backup and a manually approved restore drill.
- Architecture diagram updated in [`docs/architecture.svg`](architecture.svg).

### Observability profile

When `enable_observability = true`, Terraform creates separate private, encrypted and versioned S3 buckets and dedicated IRSA roles for Loki and Tempo. Argo CD installs pinned releases of kube-prometheus-stack, Loki, Grafana Alloy and Tempo. The profile also enables the application's `ServiceMonitor`, provisions an internal Grafana with a generated admin Secret, loads the BulletinBoard dashboard and creates baseline availability alerts.

The design follows the usual separation of metrics, logs and traces: Prometheus/Grafana/Alertmanager for metrics and alerts, Loki/Alloy for logs, and Tempo/Alloy OTLP for traces. Alloy's OTLP receiver is ready, but the application itself does not yet emit OpenTelemetry spans.

## Validation performed

- `terraform fmt -check -recursive` — passed.
- `terraform validate` — passed.
- Terraform bootstrap template rendered successfully with observability enabled and disabled; both generated scripts passed `bash -n`.
- Kustomize rendered `gitops/apps` and `gitops/observability` successfully.
- Helm templates rendered successfully for kube-prometheus-stack 88.6.1, Loki 7.3.0, Tempo 1.24.3 and Alloy 1.12.1.
- Render assertions confirmed the 720-hour Tempo retention, dedicated service accounts, Alloy OTLP ports and BulletinBoard alert rules.
- Frontend `npm run lint` and `npm run build` — passed. Vite reports a non-blocking bundle-size warning.
- Frontend production image build and non-root NGINX configuration check — passed.
- .NET solution tests — 6 passed, 0 failed.
- SVG/XML and `git diff --check` — passed.

The repository does not currently have `actionlint`, `shellcheck`, `trivy` or `checkov` installed locally, so those checks are configured in CI or remain to be run in a dedicated security pipeline.

## Findings and improvement areas

### Critical before public internet exposure

**PR-01 — No identity, authorization or moderation.**  The board accepts anonymous display names and messages. Reset/delete protection is optional, and the default Helm values leave it disabled. This is acceptable for a trusted demo network, but not for an untrusted public audience. Add an identity provider, authenticated moderator/admin actions, abuse reporting, content controls and an audit trail.

**PR-02 — Secure public ingress is opt-in.**  The default chart uses `http://bulletinboard.local` and TLS is enabled only through the environment-specific cert-manager path. A public launch needs a real hostname, HTTPS redirect, certificate renewal monitoring, secure headers, an authenticated admin path and an appropriate edge/WAF/rate-limit policy.

### High priority for a multi-replica production service

**PR-03 — Realtime delivery degrades silently to process-local fan-out.**  If Redis is absent or unavailable, each API replica only notifies its own connected clients. That is correct for the one-replica demo but can lose cross-replica realtime delivery. Hosted scale-out should make Redis a required, monitored dependency or use a durable broker with an explicit degraded-state alert. See [`webapp/RealtimeBroadcaster.cs`](../webapp/RealtimeBroadcaster.cs).

**PR-04 — Alerting and tracing still need an operational destination.**  A secret-backed Alertmanager webhook is now configurable, but the destination and on-call routing remain environment-specific. Alloy and Tempo accept OTLP, but the API has no OpenTelemetry instrumentation. Configure the receiver, on-call routing and silences; instrument HTTP, MongoDB and WebSocket paths with trace IDs correlated to structured logs.

**PR-05 — Image signing is not enforced at admission and deployment uses mutable tags.**  CI signs image digests, but the Helm deployment references a SHA tag and the cluster has no Kyverno/cosign admission policy verifying signatures. Prefer digest-pinned manifests and enforce provenance/signature policy in the cluster.

**PR-06 — EKS hardening is available but not automatically selected.**  The Terraform module now supports KMS-backed Kubernetes Secrets encryption, control-plane logs, API endpoint access controls and EKS Access Entries. The production example enables these settings, but the operator must provide valid runner/VPN CIDRs and IAM principals; network policies and strict Pod Security enforcement still need environment testing.

**PR-07 — Backup protection is present but recovery is not fully proven.**  S3 backup storage is private, encrypted, versioned and retained, and a dry-run restore workflow exists. A production launch still needs immutable/locked backup policy where required, cross-account or cross-region copies, defined RPO/RTO, an isolated full restore test and an evidence log of the result.

### Medium priority

**PR-09 — Test coverage is useful but not production-complete.**  Current tests cover validation and the in-memory repository. Add MongoDB integration tests, WebSocket multi-client tests, Redis backplane tests, health/probe tests, Helm schema/render tests, frontend unit/e2e tests, load tests and failure-injection tests.

**PR-10 — Kubernetes guardrails are partly optional.**  The production bootstrap now adds ResourceQuota/LimitRange, non-root security contexts and Pod Security audit/warn labels. The default demo remains one replica, and NetworkPolicy, strict Pod Security enforcement, anti-affinity/topology spread and namespace-level network controls still need a tested production profile.

**PR-11 — Operational telemetry should grow beyond custom counters.**  Metrics currently cover posts, resets, deletes and WebSocket client count. Add request rate/latency/status histograms, dependency latency, websocket connection/error counters, structured JSON logs and SLO dashboards. Alert rules should be tied to documented SLOs rather than only deployment availability.

**PR-12 — Secret lifecycle and operator access need a defined process.**  The generated Grafana password is kept in-cluster, which avoids Git/state exposure, but rotation, recovery and authenticated operator access are not automated. Use an external secret/SSO path for hosted environments and document break-glass access.

**PR-13 — Supply-chain and upgrade checks need automation.**  Argo CD installation is fetched from the upstream stable manifest, and chart/image updates depend on manual review. Pin the Argo install revision or vendor the manifest, add Renovate/Dependabot, and run policy/dependency/image checks on pull requests as well as on publish.

**PR-14 — Frontend bundle splitting can improve mobile performance.**  The production build succeeds, but Vite warns that the main JavaScript chunk is above 500 kB. Split or lazy-load non-critical code if the UI grows.

## Release gate

The template is ready to showcase as an architecture and automation example. Before calling a deployed instance production-grade, close PR-01 through PR-07 at minimum, then demonstrate:

1. authenticated moderator/admin flows and abuse controls;
2. HTTPS and private operator access;
3. a multi-replica load test with Redis and no missed WebSocket events;
4. a tested restore with measured RPO/RTO;
5. actionable Alertmanager notifications and traces in Grafana;
6. admission-enforced signed image deployment;
7. EKS audit logging, KMS encryption, network/pod guardrails and documented runbooks.

**Final assessment:** infrastructure/template quality is strong and coherent; the application is production-minded, but intentionally not yet a fully production-grade public service until the identity, edge-security, multi-replica correctness, recovery and operations gates are completed.
