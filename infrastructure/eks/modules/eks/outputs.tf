################################################
# EKS Module Outputs
################################################

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint of the EKS cluster API server"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate authority data required to connect to the EKS cluster"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "node_group_name" {
  description = "Name of the EKS managed node group"
  value       = aws_eks_node_group.this.node_group_name
}

output "node_role_arn" {
  description = "IAM role ARN associated with the EKS worker nodes"
  value       = aws_iam_role.eks_node_role.arn
}

output "oidc_provider_url" {
  description = "OIDC issuer URL for the EKS cluster"
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider associated with the EKS cluster"
  value       = aws_iam_openid_connect_provider.eks.arn
}
