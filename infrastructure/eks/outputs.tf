# infrastructure/eks/outputs.tf

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

output "external_secrets_role_arn" {
  description = "IRSA role used by External Secrets Operator"
  value       = aws_iam_role.external_secrets.arn
}

output "mongodb_secret_name" {
  description = "AWS Secrets Manager name to populate with MongoDB credentials"
  value       = var.mongodb_secret_name
}

output "mongodb_backup_bucket_name" {
  description = "S3 bucket used by the optional MongoDB backup CronJob"
  value       = local.mongodb_backup_bucket_name
}

output "mongodb_backup_role_arn" {
  description = "IRSA role used by the optional MongoDB backup and restore jobs"
  value       = local.mongodb_backup_role_arn
}

output "observability_logs_bucket_name" {
  description = "S3 bucket used by Loki when the observability profile is enabled"
  value       = try(aws_s3_bucket.observability["logs"].bucket, "")
}

output "observability_traces_bucket_name" {
  description = "S3 bucket used by Tempo when the observability profile is enabled"
  value       = try(aws_s3_bucket.observability["traces"].bucket, "")
}

output "observability_loki_role_arn" {
  description = "IRSA role used by Loki when the observability profile is enabled"
  value       = try(aws_iam_role.observability_loki[0].arn, "")
}

output "observability_tempo_role_arn" {
  description = "IRSA role used by Tempo when the observability profile is enabled"
  value       = try(aws_iam_role.observability_tempo[0].arn, "")
}

output "eks_secrets_kms_key_arn" {
  description = "Customer-managed KMS key ARN used for EKS Kubernetes Secrets encryption when enabled"
  value       = try(aws_kms_key.eks_secrets[0].arn, "")
}

output "argocd_bootstrap_status" {
  description = "Whether Terraform will bootstrap Argo CD after the cluster is ready"
  value       = var.bootstrap_argocd
}
