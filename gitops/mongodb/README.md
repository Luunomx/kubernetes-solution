# MongoDB GitOps resources

This directory contains the MongoDB workload resources managed by Argo CD:

- a three-member MongoDB Community replica set;
- encrypted `gp3` persistent volumes.

Terraform bootstraps the environment-specific `ClusterSecretStore` and `ExternalSecret` after the External Secrets Operator CRD is available. This keeps the AWS region, secret name and IRSA role out of Git while still making the first `terraform apply` complete the cluster wiring.

When `enable_mongodb_backup = true`, Terraform also creates a private S3 bucket, a bucket-scoped IRSA role and two jobs in the `bulletinboard` namespace:

- `mongodb-backup` runs daily and uploads a compressed `mongodump` outside the cluster;
- `mongodb-restore-drill` is suspended by default and can be started manually to download the newest backup and verify it with `mongorestore --dryRun`.

The backup bucket uses S3 versioning, server-side encryption, public-access blocking and a retention lifecycle. It is intentionally not `force_destroy`, so a destroy cannot silently remove backup data. The GitHub Actions workflow `.github/workflows/mongodb-restore-drill.yml` starts the suspended drill after a production-environment approval.
