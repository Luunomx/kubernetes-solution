variable "name" {
  description = "Prefix name for ALB resources"
}

variable "vpc_id" {
  description = "VPC ID"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of public subnet IDs"
}

variable "sg_id" {
  description = "Security group ID"
}

variable "manager_instance_id" {
  description = "ID of the Swarm manager instance"
}

variable "worker_instance_ids" {
  type        = list(string)
  description = "IDs of the Swarm worker instances"
}
