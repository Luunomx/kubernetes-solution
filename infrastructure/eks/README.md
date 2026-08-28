# AWS/EKS infrastructure

This is the infrastructure track for the BulletinBoard demo. It provisions the AWS building blocks used by the Kubernetes deployment: networking, EKS, the EBS CSI add-on, IRSA roles for External Secrets, optional MongoDB backups and optional observability storage, and the empty Secrets Manager container for MongoDB credentials. Container images are published to GHCR. After EKS is ready, Terraform bootstraps Argo CD and registers the GitOps root application. The NGINX Ingress Controller then provisions the public load balancer through Kubernetes.

## Before applying

Copy the example variables file and review the environment-specific settings for your own AWS account:

```sh
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.local.hcl
# Edit backend.local.hcl with your own state bucket and lock table names.
terraform init -backend-config=backend.local.hcl
terraform validate
terraform plan
```

For the hosted profile, start from `terraform.tfvars.production.example`
instead. It enables the production application profile and documents the
required TLS, backup, observability, EKS KMS, control-plane logging, API
endpoint and access entry settings. Replace all example ARNs, DNS values and
CIDRs before planning.

`terraform.tfvars` and `backend.local.hcl` are ignored by Git. Review the plan carefully and destroy the environment when it is no longer needed to avoid AWS charges.

Terraform expects `aws` and `kubectl` to be installed locally for the post-EKS bootstrap. The bootstrap creates the `external-secrets` service account with the generated IRSA role, installs Argo CD from `gitops/bootstrap`, waits for the Argo CD and External Secrets CRDs, and applies the root application. Argo CD then installs the remaining cluster services and application resources from Git.

The MongoDB secret container is created without a value. Populate it after `terraform apply`:

```sh
aws secretsmanager put-secret-value \
  --secret-id "$(terraform output -raw mongodb_secret_name)" \
  --secret-string '{"username":"root","password":"replace-me"}'
```

Secret values are deliberately not passed through Terraform, which keeps them out of Terraform state. If the secret already exists, set `create_mongodb_secret = false` and keep the same `mongodb_secret_name`.

For off-cluster backups, set `enable_mongodb_backup = true`. Terraform creates a private versioned S3 bucket unless `mongodb_backup_bucket_name` is supplied, applies the retention lifecycle and grants only the `mongodb-backup` service account access to that bucket. The backup CronJob runs daily; `mongodb-restore-drill` stays suspended until the manual restore workflow starts it. S3 backup objects are not deleted by `terraform destroy` because the bucket uses `force_destroy = false`.

For Argo CD Notifications, create the destination separately so its URL does not enter Git or Terraform state:

```sh
kubectl -n argocd create secret generic argocd-notifications-secret \
  --from-literal=webhook-url='https://example.invalid/bulletinboard-events'
```

Then set `enable_argocd_notifications = true`. The bootstrap configures sync-success, sync-failure and health-degraded templates for the `bulletinboard` Application.

For alert delivery, create the named Secret in the `observability` namespace
with a `webhook-url` key, then set
`enable_alertmanager_notifications = true`. The production example uses
`alertmanager-webhook`; the bootstrap fails closed if the Secret is missing.

For the production observability profile, set `enable_observability = true`. Terraform creates separate private, encrypted and versioned S3 buckets for Loki logs and Tempo traces, with one least-privilege IRSA role per component. The bootstrap creates the `observability` namespace, the Loki/Tempo service accounts and a generated Grafana admin Secret. Argo CD then installs Prometheus Operator, Prometheus, Grafana, Alertmanager, Loki, Grafana Alloy and Tempo. Grafana is intentionally internal-only; see [`gitops/observability/README.md`](../../gitops/observability/README.md) for access and the dashboard.

Set `production_profile = true` for the hosted application defaults. This keeps
the backend at one replica until `enable_redis_realtime = true` and the named
Redis/Valkey Secret exist, but enables frontend redundancy, HPA/PDB, non-root
security settings, namespace quotas and reset-key protection. EKS hardening is
configured independently with `enable_eks_secrets_encryption`,
`cluster_enabled_log_types`, `cluster_endpoint_*` and
`cluster_access_entries`. A private-only cluster endpoint requires the runner
performing bootstrap to be inside the VPC or connected to it.

For a one-trigger setup from GitHub, run `.github/workflows/provision-and-deploy.yml`. Configure the AWS OIDC role, globally unique `TF_STATE_BUCKET` and `TF_LOCK_TABLE`, and `MONGODB_SECRET_JSON` as repository secrets for a new MongoDB secret. The workflow can build/scan/sign the current images, creates the remote state backend if necessary, detects/reuses an existing MongoDB secret, waits for the `production` Environment approval, applies this Terraform track idempotently and bootstraps Argo CD. Set the `ENABLE_OBSERVABILITY` repository variable to `true` to include the full metrics/logs/traces profile in the same trigger. Set `publish_images=false` for a pure infrastructure rerun after the images already exist. Subsequent application pushes use `.github/workflows/publish-images.yml` and Argo CD handles the rollout. The AWS OIDC provider and role are the only unavoidable one-time bootstrap: the workflow must have an identity before it can create AWS resources.
