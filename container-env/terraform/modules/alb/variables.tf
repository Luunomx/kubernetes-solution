################################################
# ALB Module Variables (for EKS)
################################################

variable "name" {
  type        = string
  description = "Prefix name for all ALB resources"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the ALB will be created"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs to associate with the ALB"
}

variable "sg_id" {
  type        = string
  description = "Security group ID for the ALB"
}
