################################################
# Optional production observability storage and IRSA
################################################

variable "enable_observability" {
  type        = bool
  description = "Deploy the production observability profile through Argo CD."
  default     = false
}

variable "observability_logs_bucket_name" {
  type        = string
  description = "Optional globally unique S3 bucket name for Loki logs."
  default     = null

  validation {
    condition     = var.observability_logs_bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.observability_logs_bucket_name))
    error_message = "observability_logs_bucket_name must be a valid S3 bucket name."
  }
}

variable "observability_traces_bucket_name" {
  type        = string
  description = "Optional globally unique S3 bucket name for Tempo traces."
  default     = null

  validation {
    condition     = var.observability_traces_bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.observability_traces_bucket_name))
    error_message = "observability_traces_bucket_name must be a valid S3 bucket name."
  }
}

variable "observability_retention_days" {
  type        = number
  description = "Number of days to retain Loki and Tempo object-storage data."
  default     = 30

  validation {
    condition     = var.observability_retention_days >= 7
    error_message = "observability_retention_days must be at least 7 days."
  }
}

locals {
  observability_bucket_inputs = {
    logs   = var.observability_logs_bucket_name
    traces = var.observability_traces_bucket_name
  }
}

resource "aws_s3_bucket" "observability" {
  for_each = var.enable_observability ? local.observability_bucket_inputs : {}

  bucket        = each.value
  bucket_prefix = each.value == null ? "${var.name}-observability-${each.key}-" : null
  force_destroy = false

  tags = {
    Name      = "${var.name}-observability-${each.key}"
    ManagedBy = "Terraform"
    Purpose   = "Production observability ${each.key} storage"
  }
}

resource "aws_s3_bucket_public_access_block" "observability" {
  for_each = aws_s3_bucket.observability

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "observability" {
  for_each = aws_s3_bucket.observability

  bucket = each.value.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "observability" {
  for_each = aws_s3_bucket.observability

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "observability" {
  for_each = aws_s3_bucket.observability

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "observability" {
  for_each = aws_s3_bucket.observability

  bucket = each.value.id

  rule {
    id     = "expire-observability-data"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.observability_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.observability_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "observability_bucket_transport" {
  for_each = aws_s3_bucket.observability

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [each.value.arn, "${each.value.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "observability" {
  for_each = aws_s3_bucket.observability

  bucket = each.value.id
  policy = data.aws_iam_policy_document.observability_bucket_transport[each.key].json
}

locals {
  observability_bucket_arns = {
    for kind, bucket in aws_s3_bucket.observability : kind => bucket.arn
  }
}

data "aws_iam_policy_document" "observability_loki_assume_role" {
  count = var.enable_observability ? 1 : 0

  statement {
    sid     = "AllowLokiServiceAccount"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:observability:loki"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "observability_loki" {
  count = var.enable_observability ? 1 : 0

  name               = "${var.name}-observability-loki-role"
  assume_role_policy = data.aws_iam_policy_document.observability_loki_assume_role[0].json
}

data "aws_iam_policy_document" "observability_loki_access" {
  count = var.enable_observability ? 1 : 0

  statement {
    sid       = "ListLogsBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [try(local.observability_bucket_arns["logs"], "")]
  }

  statement {
    sid    = "ReadWriteLogObjects"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:ListMultipartUploadParts",
      "s3:PutObject"
    ]
    resources = ["${try(local.observability_bucket_arns["logs"], "")}/*"]
  }
}

resource "aws_iam_role_policy" "observability_loki_access" {
  count = var.enable_observability ? 1 : 0

  name   = "read-write-observability-logs"
  role   = aws_iam_role.observability_loki[0].id
  policy = data.aws_iam_policy_document.observability_loki_access[0].json
}

data "aws_iam_policy_document" "observability_tempo_assume_role" {
  count = var.enable_observability ? 1 : 0

  statement {
    sid     = "AllowTempoServiceAccount"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:observability:tempo"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "observability_tempo" {
  count = var.enable_observability ? 1 : 0

  name               = "${var.name}-observability-tempo-role"
  assume_role_policy = data.aws_iam_policy_document.observability_tempo_assume_role[0].json
}

data "aws_iam_policy_document" "observability_tempo_access" {
  count = var.enable_observability ? 1 : 0

  statement {
    sid       = "ListTracesBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [try(local.observability_bucket_arns["traces"], "")]
  }

  statement {
    sid    = "ReadWriteTraceObjects"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:ListMultipartUploadParts",
      "s3:PutObject"
    ]
    resources = ["${try(local.observability_bucket_arns["traces"], "")}/*"]
  }
}

resource "aws_iam_role_policy" "observability_tempo_access" {
  count = var.enable_observability ? 1 : 0

  name   = "read-write-observability-traces"
  role   = aws_iam_role.observability_tempo[0].id
  policy = data.aws_iam_policy_document.observability_tempo_access[0].json
}
