variable "project_name" {
  type        = string
  description = "Prefix for all resource names"
  default     = "assignment2"
}

variable "ec2_key_name" {
  type        = string
  description = "Existing EC2 Key Pair name for SSH (optional)"
  default     = ""
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for Swarm nodes"
  default     = "t3.small"
}

variable "manager_desired" {
  type        = number
  description = "Desired manager node count"
  default     = 1
}

variable "worker_desired" {
  type        = number
  description = "Desired worker node count"
  default     = 2
}
