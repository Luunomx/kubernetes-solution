################################################
# EKS Module Variables
################################################

variable "name" {
  type        = string
  description = "Prefix name for EKS resources"
}

variable "region" {
  type        = string
  description = "AWS region for deployment"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where EKS cluster will be deployed"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for EKS cluster and node groups"
}

variable "sg_ids" {
  type        = list(string)
  description = "List of security group IDs for EKS cluster networking"
}

variable "instance_profile" {
  type        = string
  description = "IAM instance profile name for EKS nodes"
  default     = null
}

variable "cluster_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster"
  default     = "1.30"
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
