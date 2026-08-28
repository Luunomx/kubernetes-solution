################################################
# Deployment profile and optional EKS hardening
################################################

variable "deployment_profile" {
  type        = string
  description = "Deployment intent. Demo keeps the low-friction defaults; production enables the hosted application profile in the bootstrap values."
  default     = "demo"

  validation {
    condition     = contains(["demo", "production"], var.deployment_profile)
    error_message = "deployment_profile must be either 'demo' or 'production'."
  }
}

variable "production_profile" {
  type        = bool
  description = "Apply production-oriented Helm settings such as non-root pods, frontend redundancy and protected reset operations."
  default     = false
}

variable "enable_redis_realtime" {
  type        = bool
  description = "Use the externally managed Redis Secret for cross-replica WebSocket fan-out."
  default     = false
}

variable "redis_secret_name" {
  type        = string
  description = "Kubernetes Secret containing the Redis connection string."
  default     = "bulletinboard-redis"
}

variable "enable_alertmanager_notifications" {
  type        = bool
  description = "Configure Alertmanager to deliver alerts through a pre-created Kubernetes Secret-backed webhook."
  default     = false
}

variable "alertmanager_secret_name" {
  type        = string
  description = "Kubernetes Secret containing the Alertmanager webhook-url key."
  default     = "alertmanager-webhook"
}

locals {
  effective_production_profile = var.production_profile || var.deployment_profile == "production"
}

variable "enable_eks_secrets_encryption" {
  type        = bool
  description = "Create a customer-managed KMS key and encrypt Kubernetes Secrets at rest in EKS."
  default     = false
}

variable "cluster_endpoint_private_access" {
  type        = bool
  description = "Allow nodes and private network clients to reach the EKS API endpoint."
  default     = true
}

variable "cluster_endpoint_public_access" {
  type        = bool
  description = "Expose the EKS API endpoint publicly. Restrict public_access_cidrs when enabled."
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDR allow-list for public EKS API access. Use a VPN or runner egress CIDR for hosted environments."
  default     = ["0.0.0.0/0"]
}

variable "cluster_enabled_log_types" {
  type        = set(string)
  description = "EKS control-plane log types to export to CloudWatch."
  default     = []

  validation {
    condition = alltrue([
      for log_type in var.cluster_enabled_log_types : contains(
        ["api", "audit", "authenticator", "controllerManager", "scheduler"],
        log_type
      )
    ])
    error_message = "cluster_enabled_log_types contains an unsupported EKS control-plane log type."
  }
}

variable "cluster_access_entries" {
  type = map(object({
    principal_arn     = string
    type              = optional(string, "STANDARD")
    kubernetes_groups = optional(list(string), [])
    policy_arns       = optional(set(string), [])
  }))
  description = "Optional EKS API access entries. Keep operator IAM principals here instead of committing aws-auth mappings."
  default     = {}
}

resource "aws_kms_key" "eks_secrets" {
  count = var.enable_eks_secrets_encryption ? 1 : 0

  description             = "KMS key for ${var.name} EKS Kubernetes Secrets encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name      = "${var.name}-eks-secrets"
    ManagedBy = "Terraform"
    Purpose   = "EKS Kubernetes Secrets encryption"
  }
}

resource "aws_kms_alias" "eks_secrets" {
  count = var.enable_eks_secrets_encryption ? 1 : 0

  name          = "alias/${var.name}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets[0].key_id
}
