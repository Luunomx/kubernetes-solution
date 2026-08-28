################################################
# Optional MongoDB off-cluster backups
################################################

variable "enable_mongodb_backup" {
  type        = bool
  description = "Enable the S3-backed MongoDB backup CronJob and manual restore drill."
  default     = false
}

variable "mongodb_backup_bucket_name" {
  type        = string
  description = "Optional globally unique S3 bucket name for MongoDB backups. Terraform generates one when omitted."
  default     = null

  validation {
    condition     = var.mongodb_backup_bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.mongodb_backup_bucket_name))
    error_message = "mongodb_backup_bucket_name must be a valid S3 bucket name."
  }
}

variable "mongodb_backup_retention_days" {
  type        = number
  description = "Number of days to retain MongoDB backup objects."
  default     = 30

  validation {
    condition     = var.mongodb_backup_retention_days >= 7
    error_message = "mongodb_backup_retention_days must be at least 7 days."
  }
}

resource "aws_s3_bucket" "mongodb_backup" {
  count = var.enable_mongodb_backup ? 1 : 0

  bucket        = var.mongodb_backup_bucket_name
  bucket_prefix = var.mongodb_backup_bucket_name == null ? "${var.name}-mongo-backup-" : null
  force_destroy = false

  tags = {
    Name      = "${var.name}-mongodb-backups"
    ManagedBy = "Terraform"
    Purpose   = "MongoDB backup and restore drill"
  }
}

resource "aws_s3_bucket_public_access_block" "mongodb_backup" {
  count = var.enable_mongodb_backup ? 1 : 0

  bucket = aws_s3_bucket.mongodb_backup[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "mongodb_backup" {
  count = var.enable_mongodb_backup ? 1 : 0

  bucket = aws_s3_bucket.mongodb_backup[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "mongodb_backup" {
  count = var.enable_mongodb_backup ? 1 : 0

  bucket = aws_s3_bucket.mongodb_backup[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mongodb_backup" {
  count = var.enable_mongodb_backup ? 1 : 0

  bucket = aws_s3_bucket.mongodb_backup[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "mongodb_backup" {
  count = var.enable_mongodb_backup ? 1 : 0

  bucket = aws_s3_bucket.mongodb_backup[0].id

  rule {
    id     = "expire-mongodb-backups"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.mongodb_backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.mongodb_backup_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "mongodb_backup_bucket_transport" {
  count = var.enable_mongodb_backup ? 1 : 0

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.mongodb_backup[0].arn, "${aws_s3_bucket.mongodb_backup[0].arn}/*"]

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

resource "aws_s3_bucket_policy" "mongodb_backup" {
  count = var.enable_mongodb_backup ? 1 : 0

  bucket = aws_s3_bucket.mongodb_backup[0].id
  policy = data.aws_iam_policy_document.mongodb_backup_bucket_transport[0].json
}

locals {
  mongodb_backup_bucket_arn  = var.enable_mongodb_backup ? aws_s3_bucket.mongodb_backup[0].arn : ""
  mongodb_backup_bucket_name = var.enable_mongodb_backup ? aws_s3_bucket.mongodb_backup[0].bucket : ""
  mongodb_backup_role_arn    = var.enable_mongodb_backup ? aws_iam_role.mongodb_backup[0].arn : ""
}

data "aws_iam_policy_document" "mongodb_backup_assume_role" {
  count = var.enable_mongodb_backup ? 1 : 0

  statement {
    sid     = "AllowMongoDBBackupServiceAccount"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:bulletinboard:mongodb-backup"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mongodb_backup" {
  count = var.enable_mongodb_backup ? 1 : 0

  name               = "${var.name}-mongodb-backup-role"
  assume_role_policy = data.aws_iam_policy_document.mongodb_backup_assume_role[0].json
}

data "aws_iam_policy_document" "mongodb_backup_access" {
  count = var.enable_mongodb_backup ? 1 : 0

  statement {
    sid       = "ListBackupBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.mongodb_backup_bucket_arn]
  }

  statement {
    sid    = "ReadWriteBackupObjects"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["${local.mongodb_backup_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "mongodb_backup_access" {
  count = var.enable_mongodb_backup ? 1 : 0

  name   = "read-write-mongodb-backups"
  role   = aws_iam_role.mongodb_backup[0].id
  policy = data.aws_iam_policy_document.mongodb_backup_access[0].json
}
