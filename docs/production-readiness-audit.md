# Production deployment runbook

This document is the high-level, ordered plan for taking the template from a
clean repository to a running AWS/EKS environment. It describes what must be
prepared, what the automation does, what must be verified and what still has
to be decided before exposing the application publicly.

No AWS account, EKS cluster or production deployment has been created from
this repository during development. The steps below are the intended execution
path for a future environment.

The visual companion is
[`deployment-flow.svg`](deployment-flow.svg). The existing
[`architecture.svg`](architecture.svg) explains the system relationships;
`deployment-flow.svg` explains the ordered setup path.

## 1. Choose the target profile

Use one of the two supported modes:

- `demo`: the smallest EKS showcase profile. It is suitable for a trusted
  environment and keeps scale-out dependencies optional.
- `production`: the hardened application profile. It enables non-root pods,
  frontend redundancy, HPA/PDB settings, namespace quotas, Pod Security
  audit/warn labels and reset-key protection.

The production profile does not silently invent environment-specific values.
TLS, off-cluster backups, observability, Alertmanager delivery and Redis are
explicit settings because each requires a real hostname, destination, secret
or operational decision. Start from
[`infrastructure/eks/terraform.tfvars.production.example`](../infrastructure/eks/terraform.tfvars.production.example)
and replace every placeholder.

## 2. Prepare the external prerequisites

Before the first run, provide:

1. An AWS account, target region, service quotas and a naming convention for
   the cluster, state resources, secrets and buckets.
2. A GitHub repository containing this template and permission to publish its
   frontend and backend images to that repository's GHCR namespace.
3. A domain and Route 53 hosted zone if public HTTPS is required.
4. An operator or CI runner with AWS, Terraform, `kubectl` and Docker access.
   A GitHub-hosted runner normally needs a restricted public EKS API endpoint;
   a private-only endpoint requires a self-hosted runner inside or connected to
   the VPC.
5. An agreed operator access model. EKS Access Entries should contain the
   smallest set of IAM principals and policies needed to operate the cluster.

The AWS account must allow the bootstrap role to create or manage the VPC,
EKS, node group, load balancer integration, EBS CSI, IAM/IRSA, Secrets Manager,
S3, DynamoDB, Route 53 and the optional observability resources.

## 3. Establish the one unavoidable bootstrap identity

The first AWS identity cannot be created by the workflow that needs to
authenticate with AWS. Create these pieces once, outside the workflow:

- A GitHub Actions OIDC provider in AWS.
- An IAM role whose trust policy is restricted to this repository and the
  intended branch or environment.
- Permissions for that role to bootstrap Terraform state and manage only the
  resources required by `infrastructure/eks/`.
- A protected GitHub Environment named `production` with required reviewers.

Store the role ARN as the GitHub secret `AWS_ROLE_ARN`. Do not use a long-lived
AWS access key in GitHub.

## 4. Configure GitHub variables and secrets

The single-trigger workflow is
[`provision-and-deploy.yml`](../.github/workflows/provision-and-deploy.yml).
Configure its repository or environment variables before dispatching it.

### Required baseline variables

- `AWS_REGION`
- `CLUSTER_NAME`
- `CLUSTER_VERSION`
- `DEPLOYMENT_PROFILE=production`
- `PRODUCTION_PROFILE=true`
- `MONGODB_SECRET_NAME`
- `GITOPS_REVISION` is supplied by the workflow input and should normally be
  `main`.

### Production infrastructure variables

- `ENABLE_CERT_MANAGER_TLS=true`, `ROUTE53_HOSTED_ZONE_ID`, `TLS_HOST` and
  `ACME_EMAIL` for HTTPS.
- `ENABLE_MONGODB_BACKUP=true` and the retention/bucket settings.
- `ENABLE_OBSERVABILITY=true` and optional explicit log/trace bucket names.
- `ENABLE_EKS_SECRETS_ENCRYPTION=true`.
- `CLUSTER_ENDPOINT_PRIVATE_ACCESS`, `CLUSTER_ENDPOINT_PUBLIC_ACCESS` and
  `CLUSTER_PUBLIC_ACCESS_CIDRS`. Never leave `0.0.0.0/0` as the production
  value; use the runner or VPN egress CIDR.
- `CLUSTER_ENABLED_LOG_TYPES`, normally including `api`, `audit`,
  `authenticator`, `controllerManager` and `scheduler`.
- `CLUSTER_ACCESS_ENTRIES_JSON` with the approved IAM principal ARNs and EKS
  access policies.

### Optional dependency variables

- `ENABLE_REDIS_REALTIME=true` and `REDIS_SECRET_NAME` only after the named
  Kubernetes Secret exists in the `bulletinboard` namespace with a
  `connection-string` key. This is required before running more than one
  backend replica.
- `ENABLE_ARGOCD_NOTIFICATIONS=true` only after
  `argocd-notifications-secret` exists in the `argocd` namespace with a
  `webhook-url` key.
- `ENABLE_ALERTMANAGER_NOTIFICATIONS=true` only after the named Alertmanager
  Secret exists in the `observability` namespace with a `webhook-url` key.

Keep the following as GitHub secrets, never committed files or plain
repository variables:

- `AWS_ROLE_ARN`
- `TF_STATE_BUCKET`
- `TF_LOCK_TABLE`
- `MONGODB_SECRET_JSON` when the MongoDB secret is new or must be rotated; it
  must contain a JSON object with `username` and `password` strings.

For a new cluster, notification Secrets cannot already exist in the new
namespaces. The clean sequence is to run the first bootstrap with the
corresponding notification switch disabled, create the Secret after Argo CD
and the namespace exist, then rerun the workflow with the switch enabled.

## 5. Bootstrap remote Terraform state

The workflow calls
[`bootstrap-state.sh`](../infrastructure/eks/scripts/bootstrap-state.sh)
before Terraform initialization. It creates or reuses the S3 state bucket and
DynamoDB lock table, then applies state protection such as private access,
versioning, encryption, a deny-insecure-transport policy and point-in-time
recovery where supported.

The state bucket and lock table names must be globally/account-appropriate and
must not be shared casually between environments. Terraform state and plans
must remain outside Git.

## 6. Run the first provision-and-deploy chain

Dispatch `provision-and-deploy.yml` with:

- `publish_images=true` for the first environment, so the current frontend and
  backend are tested, built, scanned, signed and published to GHCR.
- `bootstrap_argocd=true`.
- `create_mongodb_secret=true` if the AWS Secrets Manager secret does not yet
  exist.
- `gitops_revision=main` or the reviewed release revision.

When `publish_images=true`, the reusable `publish-images.yml` job completes
first. Only after that job succeeds does the provisioning job perform this
sequence:

1. Checks out the repository and validates required settings.
2. Authenticates to AWS with GitHub OIDC.
3. Verifies or creates the MongoDB secret container without putting its value
   in Terraform state.
4. Creates the remote state backend and initializes Terraform.
5. Plans the VPC, private EKS node subnets, EKS cluster, node group, EBS CSI,
   IRSA roles, optional KMS/logging/access controls, storage buckets and
   secret wiring.
6. Waits for the protected `production` Environment approval.
7. Applies the approved Terraform plan.
8. Populates the MongoDB secret when `MONGODB_SECRET_JSON` was supplied.
9. Updates kubeconfig and bootstraps Argo CD, External Secrets and the
   environment-specific Argo Applications.

The workflow is idempotent: an existing cluster and MongoDB secret are reused
and updated rather than recreated. A later infrastructure-only run can set
`publish_images=false`.

## 7. Let Argo CD reconcile the cluster

The Terraform-generated bootstrap installs the Argo CD base and registers the
GitOps root application. Argo CD then reconciles the resources in this order:

1. `gitops/apps/` and the root application.
2. NGINX Ingress Controller and its AWS load balancer integration.
3. External Secrets Operator and its AWS-backed secret store.
4. cert-manager and the Route 53 ACME issuer when TLS is enabled.
5. MongoDB Community Operator, the three-member MongoDB replica set and gp3
   persistent storage.
6. The BulletinBoard Helm release, including the production profile settings,
   reset-key Secret reference, ingress and optional Redis backplane.
7. Prometheus/Grafana/Alertmanager, Loki/Alloy and Tempo when observability is
   enabled.
8. MongoDB backup resources when off-cluster backups are enabled.

The application Helm values are kept in Git for shared defaults. Environment-
specific values such as the hostname, generated reset Secret reference,
bucket names and IRSA ARNs are injected by the Terraform bootstrap so they do
not need to be committed to the repository.

## 8. Complete DNS and edge verification

After the NGINX Ingress Controller provisions the AWS NLB:

1. Point the chosen DNS name at the NLB using the appropriate Route 53 alias
   or record.
2. Confirm that cert-manager obtains and renews the certificate through the
   Route 53 DNS-01 challenge.
3. Verify HTTPS, the application route, `/health/live`, `/health/ready`,
   `/metrics` access policy and the `/api/ws` WebSocket path.
4. Confirm that the operator interfaces remain private or authenticated. Do
   not expose Grafana, Argo CD or Kubernetes administration through the public
   application ingress without an explicit identity and edge policy.

## 9. Verify the first environment before calling it ready

The deployment is not complete when Terraform exits successfully. Confirm:

- EKS nodes are Ready and the expected node group, EBS CSI and IRSA roles are
  healthy.
- Argo Applications are `Synced` and `Healthy`, with no repeated sync errors.
- External Secrets reports Ready and the MongoDB credentials resolve.
- MongoDB has all three members available, persistent volumes are bound and
  application reads/writes work.
- The frontend and backend probes pass, HPA/PDB objects exist where enabled,
  and the namespace quota is not blocking scheduling.
- The NLB, DNS record, TLS certificate and WebSocket path work from a client
  outside the cluster.
- Redis fan-out works across backend replicas when scale-out is enabled.
- A backup object is written to the protected S3 bucket and a restore drill
  has been executed in an isolated target.
- Grafana shows application metrics and logs, and Alertmanager delivers a
  test notification to the configured destination.
- Control-plane audit logs, KMS Secrets encryption, API access restrictions,
  Pod Security settings and the intended EKS Access Entries are effective.

Record the result, timestamps, owner and evidence for the backup restore,
alert test, scale test and security checks. This becomes the environment's
initial operational record.

## 10. Close the public-production gates

The template supplies infrastructure hooks, but the application is not a
fully public production service until these decisions and tests are completed:

1. Add an identity provider, authenticated moderator/admin actions,
   authorization, abuse reporting, content moderation and an audit trail.
2. Enforce HTTPS, secure headers, edge rate limits/WAF policy and private
   operator access.
3. Make Redis or another shared broker a required, monitored dependency for
   multi-replica realtime delivery, then prove that no WebSocket events are
   missed during rollout and failure.
4. Define RPO/RTO and prove an isolated restore. Add immutable or cross-account
   backup protection if the data classification requires it.
5. Configure actionable Alertmanager routing, on-call ownership and silences.
   Add OpenTelemetry instrumentation if traces are expected in Tempo.
6. Pin images by digest and enforce cosign/provenance verification with a
   cluster admission policy such as Kyverno or an equivalent control.
7. Test and enforce NetworkPolicies, strict Pod Security, topology spreading,
   resource limits and cluster upgrade procedures.
8. Define secret rotation, break-glass access, dependency upgrades, incident
   response and rollback runbooks.

Until these gates are demonstrated in a real environment, describe the result
as a production-minded Kubernetes template rather than a production-grade
public message board.

## 11. Day-2 delivery and operations

- Application change: push to GitHub, let `publish-images.yml` test/build/scan/
  sign the images and update the SHA references; Argo CD detects the GitOps
  change and rolls out the release.
- Infrastructure change: dispatch `provision-and-deploy.yml`, review the
  Terraform plan and approve the protected production Environment.
- Operational change: update the relevant Terraform, Helm or GitOps input,
  validate locally, review the diff and reconcile through Argo CD.
- Recovery: use the approved MongoDB restore drill workflow, document the
  result and never treat a dry-run as proof of recoverability.
- Upgrades: review EKS, Argo CD, operators and chart versions deliberately;
  stage them in a non-production environment before production.
- Teardown: destroy unused environments deliberately and retain required
  backups, evidence and state according to the environment's retention policy.

## Repository map

- [`README.md`](../README.md) — local development, workflows and configuration
  overview.
- [`infrastructure/eks/`](../infrastructure/eks/) — Terraform, bootstrap,
  state backend and production example variables.
- [`gitops/`](../gitops/) — Argo CD applications and cluster services.
- [`k8s/helm/bulletinboard/`](../k8s/helm/bulletinboard/) — application chart.
- [`docs/architecture.svg`](architecture.svg) — architecture and delivery
  flow diagram.
- [`docs/deployment-flow.svg`](deployment-flow.svg) — numbered environment
  setup and operations flow.
- [`SECURITY.md`](../SECURITY.md) — secret-handling and security policy.

The next document to add, when this checklist is approved, is the exact
environment setup guide with copy/paste commands, IAM policy examples,
GitHub settings, secret creation steps and post-deploy verification commands.
