# container-env/terraform/outputs.tf

################################################
# Application Load Balancer
################################################
output "alb_dns_name" {
  description = "Public DNS of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

################################################
# EKS Cluster Outputs
################################################
output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "Certificate authority data for cluster access"
  value       = module.eks.cluster_certificate_authority_data
}

output "eks_node_group_name" {
  description = "Name of the EKS node group"
  value       = module.eks.node_group_name
}

output "eks_node_role_arn" {
  description = "ARN of the IAM role assigned to EKS worker nodes"
  value       = module.eks.node_role_arn
}

################################################
# ECR Repository
################################################
output "backend_repository_url" {
  value = module.ecr.backend_repository_url
}

output "frontend_repository_url" {
  value = module.ecr.frontend_repository_url
}

################################################
# IAM Outputs
################################################
output "iam_instance_profile_name" {
  description = "Name of the EC2 instance profile from IAM module"
  value       = module.iam.instance_profile_name
}

output "iam_role_name" {
  description = "Name of the IAM role for EC2 from IAM module"
  value       = module.iam.role_name
}

output "iam_role_arn" {
  description = "ARN of the IAM role for EC2 from IAM module"
  value       = module.iam.role_arn
}

################################################
# Security Group Outputs
################################################
output "alb_sg_id" {
  description = "Security group ID for Application Load Balancer"
  value       = module.security-group.alb_sg_id
}

output "bastion_sg_id" {
  description = "Security group ID for bastion host"
  value       = module.security-group.bastion_sg_id
}
