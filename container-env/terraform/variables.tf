################################################
# Deployment settings
################################################
variable "region" {
  type        = string
  description = "AWS region to deploy into"
  default     = "eu-west-1"
}

variable "name" {
  type        = string
  description = "Prefix name for all resources (e.g. project identifier)"
}

################################################
# SSH Key for Bastion
################################################
variable "key_name" {
  type        = string
  description = "Name of the existing AWS key pair to use for the bastion host"
}

################################################
# EKS Cluster settings
################################################
variable "cluster_version" {
  type        = string
  description = "EKS cluster version"
  default     = "1.30"
}

variable "node_instance_type" {
  type        = string
  description = "EC2 instance type for worker nodes"
  default     = "t3.medium"
}

variable "desired_capacity" {
  type        = number
  description = "Desired number of worker nodes"
  default     = 2
}

variable "max_capacity" {
  type        = number
  description = "Maximum number of worker nodes"
  default     = 3
}

variable "min_capacity" {
  type        = number
  description = "Minimum number of worker nodes"
  default     = 1
}

################################################
# AWS account & networking
################################################
variable "account_id" {
  type        = string
  description = "AWS Account ID"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "subnet_a_cidr" {
  type        = string
  description = "CIDR block for public subnet A"
}

variable "subnet_b_cidr" {
  type        = string
  description = "CIDR block for public subnet B"
}

variable "private_subnet_a_cidr" {
  type        = string
  description = "CIDR block for private subnet A"
}

variable "private_subnet_b_cidr" {
  type        = string
  description = "CIDR block for private subnet B"
}

################################################
# Bastion / Access control
################################################
variable "my_ip" {
  type        = string
  description = "Your current public IP address (for bastion SSH access)"
}
