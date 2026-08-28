################################################
# EKS Module Variables
################################################

variable "name" {
  type        = string
  description = "Prefix name for EKS resources"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for EKS cluster and node groups"
}

variable "cluster_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster"
  default     = "1.36"
}

variable "node_instance_type" {
  type        = string
  description = "EC2 instance type for worker nodes"
  default     = "t3.medium"
}

variable "desired_capacity" {
  type        = number
  description = "Desired number of worker nodes in node group"
  default     = 2
}

variable "max_capacity" {
  type        = number
  description = "Maximum number of worker nodes in node group"
  default     = 3
}

variable "min_capacity" {
  type        = number
  description = "Minimum number of worker nodes in node group"
  default     = 1
}

variable "endpoint_private_access" {
  type        = bool
  description = "Whether the EKS API endpoint is reachable from the VPC."
  default     = true
}

variable "endpoint_public_access" {
  type        = bool
  description = "Whether the EKS API endpoint is reachable publicly."
  default     = true
}

variable "public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public EKS API endpoint."
  default     = ["0.0.0.0/0"]
}

variable "enabled_cluster_log_types" {
  type        = set(string)
  description = "EKS control-plane log types to send to CloudWatch."
  default     = []
}

variable "secrets_encryption_kms_key_arn" {
  type        = string
  description = "Optional customer-managed KMS key ARN for Kubernetes Secrets encryption."
  default     = null
}

variable "access_entries" {
  type = map(object({
    principal_arn     = string
    type              = optional(string, "STANDARD")
    kubernetes_groups = optional(list(string), [])
    policy_arns       = optional(set(string), [])
  }))
  description = "Optional EKS API access entries and associated access policies."
  default     = {}
}
