################################################
# AWS Secrets Manager and IRSA
################################################

variable "mongodb_secret_name" {
  type        = string
  description = "AWS Secrets Manager name containing the MongoDB username and password JSON."
  default     = "bulletinboard/mongodb"

  validation {
    condition     = can(regex("^[A-Za-z0-9/_+=.@-]+$", var.mongodb_secret_name))
    error_message = "mongodb_secret_name may only contain AWS Secrets Manager name characters."
  }
}

variable "create_mongodb_secret" {
  type        = bool
  description = "Create the Secrets Manager container. The secret value is intentionally managed outside Terraform."
  default     = true
}

variable "enable_cert_manager_tls" {
  type        = bool
  description = "Enable Route53 DNS-01 certificate issuance for the public BulletinBoard hostname."
  default     = false
}

variable "route53_hosted_zone_id" {
  type        = string
  description = "Route53 hosted zone ID used by cert-manager DNS-01 challenges."
  default     = null

  validation {
    condition     = !var.enable_cert_manager_tls || (var.route53_hosted_zone_id != null && can(regex("^Z[A-Z0-9]+$", var.route53_hosted_zone_id)))
    error_message = "route53_hosted_zone_id must be a Route53 hosted zone ID when TLS is enabled."
  }
}

variable "tls_host" {
  type        = string
  description = "Public DNS hostname that cert-manager should issue a certificate for."
  default     = null

  validation {
    condition     = !var.enable_cert_manager_tls || (var.tls_host != null && can(regex("^(\\*\\.)?[A-Za-z0-9][A-Za-z0-9.-]+$", var.tls_host)))
    error_message = "tls_host must be a DNS hostname when TLS is enabled."
  }
}

variable "acme_email" {
  type        = string
  description = "Email address registered with the ACME issuer."
  default     = null

  validation {
    condition     = !var.enable_cert_manager_tls || (var.acme_email != null && can(regex("^[^@[:space:]]+@[^@[:space:]]+$", var.acme_email)))
    error_message = "acme_email must be a valid email address when TLS is enabled."
  }
}

variable "cert_manager_role_name" {
  type        = string
  description = "Optional explicit IAM role name for cert-manager Route53 access."
  default     = null
}

variable "enable_argocd_notifications" {
  type        = bool
  description = "Configure the bundled Argo CD Notifications controller with a generic webhook service."
  default     = false
}

resource "aws_secretsmanager_secret" "mongodb" {
  count                   = var.create_mongodb_secret ? 1 : 0
  name                    = var.mongodb_secret_name
  description             = "BulletinBoard MongoDB credentials"
  recovery_window_in_days = 7
}

data "aws_secretsmanager_secret" "mongodb" {
  count = var.create_mongodb_secret ? 0 : 1
  name  = var.mongodb_secret_name
}

locals {
  mongodb_secret_arn      = var.create_mongodb_secret ? aws_secretsmanager_secret.mongodb[0].arn : data.aws_secretsmanager_secret.mongodb[0].arn
  cert_manager_role_arn   = var.enable_cert_manager_tls ? aws_iam_role.cert_manager[0].arn : ""
  route53_hosted_zone_arn = var.route53_hosted_zone_id == null ? "" : "arn:aws:route53:::hostedzone/${var.route53_hosted_zone_id}"
}

data "aws_iam_policy_document" "external_secrets_assume_role" {
  statement {
    sid     = "AllowExternalSecretsServiceAccount"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${var.name}-external-secrets-role"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_assume_role.json
}

data "aws_iam_policy_document" "external_secrets_access" {
  statement {
    sid    = "ReadMongoDBSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue"
    ]
    resources = [local.mongodb_secret_arn]
  }
}

resource "aws_iam_role_policy" "external_secrets_access" {
  name   = "read-mongodb-secret"
  role   = aws_iam_role.external_secrets.id
  policy = data.aws_iam_policy_document.external_secrets_access.json
}

data "aws_iam_policy_document" "cert_manager_assume_role" {
  count = var.enable_cert_manager_tls ? 1 : 0

  statement {
    sid     = "AllowCertManagerServiceAccount"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:cert-manager:cert-manager"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cert_manager" {
  count              = var.enable_cert_manager_tls ? 1 : 0
  name               = coalesce(var.cert_manager_role_name, "${var.name}-cert-manager-role")
  assume_role_policy = data.aws_iam_policy_document.cert_manager_assume_role[0].json
}

data "aws_iam_policy_document" "cert_manager_route53_access" {
  count = var.enable_cert_manager_tls ? 1 : 0

  statement {
    sid    = "ManageCertificateRecords"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets"
    ]
    resources = [local.route53_hosted_zone_arn]
  }

  statement {
    sid    = "DiscoverHostedZone"
    effect = "Allow"
    actions = [
      "route53:GetChange",
      "route53:ListHostedZonesByName"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cert_manager_route53_access" {
  count  = var.enable_cert_manager_tls ? 1 : 0
  name   = "manage-route53-acme-records"
  role   = aws_iam_role.cert_manager[0].id
  policy = data.aws_iam_policy_document.cert_manager_route53_access[0].json
}

################################################
# First-cluster GitOps bootstrap
################################################

variable "bootstrap_argocd" {
  type        = bool
  description = "Bootstrap Argo CD and the root application after EKS is ready. Requires aws and kubectl locally."
  default     = true
}

variable "gitops_repository_url" {
  type        = string
  description = "Git repository URL Argo CD should watch."
  default     = "https://github.com/luunomx/kubernetes-solution.git"
}

variable "gitops_revision" {
  type        = string
  description = "Git revision Argo CD should watch."
  default     = "main"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.gitops_revision))
    error_message = "gitops_revision may only contain branch, tag or path-safe revision characters."
  }
}

resource "terraform_data" "argocd_bootstrap" {
  count = var.bootstrap_argocd ? 1 : 0

  triggers_replace = [
    module.eks.cluster_name,
    module.eks.node_group_name,
    aws_iam_role.external_secrets.arn,
    local.mongodb_secret_arn,
    local.cert_manager_role_arn,
    local.mongodb_backup_role_arn,
    local.mongodb_backup_bucket_name,
    local.observability_bucket_arns,
    try(aws_iam_role.observability_loki[0].arn, ""),
    try(aws_iam_role.observability_tempo[0].arn, ""),
    var.region,
    var.gitops_repository_url,
    var.gitops_revision,
    var.enable_cert_manager_tls,
    var.route53_hosted_zone_id,
    var.tls_host,
    var.acme_email,
    var.enable_mongodb_backup,
    var.mongodb_backup_retention_days,
    var.enable_argocd_notifications,
    var.enable_observability,
    var.production_profile,
    var.deployment_profile,
    var.enable_redis_realtime,
    var.redis_secret_name,
    var.enable_alertmanager_notifications,
    var.alertmanager_secret_name,
    var.observability_retention_days,
    var.observability_logs_bucket_name,
    var.observability_traces_bucket_name,
    filesha256("${path.module}/../../gitops/bootstrap/kustomization.yaml"),
    filesha256("${path.module}/../../gitops/observability/kustomization.yaml"),
    filesha256("${path.module}/../../gitops/observability/bulletinboard-dashboard.yaml"),
    filesha256("${path.module}/bootstrap.sh.tftpl")
  ]

  depends_on = [
    aws_iam_role_policy.external_secrets_access,
    aws_iam_role_policy.cert_manager_route53_access,
    aws_iam_role_policy.mongodb_backup_access,
    aws_iam_role_policy.observability_loki_access,
    aws_iam_role_policy.observability_tempo_access
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command = templatefile("${path.module}/bootstrap.sh.tftpl", {
      cluster_name                      = module.eks.cluster_name
      external_secrets_arn              = aws_iam_role.external_secrets.arn
      cert_manager_role_arn             = local.cert_manager_role_arn
      gitops_repository                 = var.gitops_repository_url
      gitops_revision                   = var.gitops_revision
      mongodb_secret_name               = var.mongodb_secret_name
      enable_cert_manager_tls           = var.enable_cert_manager_tls
      route53_hosted_zone_id            = var.route53_hosted_zone_id
      tls_host                          = var.tls_host
      acme_email                        = var.acme_email
      enable_mongodb_backup             = var.enable_mongodb_backup
      mongodb_backup_bucket             = local.mongodb_backup_bucket_name
      mongodb_backup_role_arn           = local.mongodb_backup_role_arn
      mongodb_backup_retention_days     = var.mongodb_backup_retention_days
      enable_argocd_notifications       = var.enable_argocd_notifications
      enable_observability              = var.enable_observability
      production_profile                = local.effective_production_profile
      enable_redis_realtime             = var.enable_redis_realtime
      redis_secret_name                 = var.redis_secret_name
      enable_alertmanager_notifications = var.enable_alertmanager_notifications
      alertmanager_secret_name          = var.alertmanager_secret_name
      observability_logs_bucket         = try(aws_s3_bucket.observability["logs"].bucket, "")
      observability_traces_bucket       = try(aws_s3_bucket.observability["traces"].bucket, "")
      observability_loki_role_arn       = try(aws_iam_role.observability_loki[0].arn, "")
      observability_tempo_role_arn      = try(aws_iam_role.observability_tempo[0].arn, "")
      observability_retention_days      = var.observability_retention_days
      repository_root                   = abspath("${path.module}/../..")
      region                            = var.region
    })
  }
}
