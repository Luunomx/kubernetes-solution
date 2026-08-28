################################################
# Terraform & Providers
################################################
terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  dynamic "assume_role" {
    for_each = var.terraform_assume_role_arn == null ? [] : [var.terraform_assume_role_arn]
    content {
      role_arn = assume_role.value
    }
  }
}

################################################
# VPC
################################################
module "vpc" {
  source = "./modules/vpc"

  region                = var.region
  name                  = var.name
  vpc_cidr              = var.vpc_cidr
  subnet_a_cidr         = var.subnet_a_cidr
  subnet_b_cidr         = var.subnet_b_cidr
  private_subnet_a_cidr = var.private_subnet_a_cidr
  private_subnet_b_cidr = var.private_subnet_b_cidr
}

################################################
# EKS Cluster
################################################
module "eks" {
  source = "./modules/eks"

  name       = var.name
  subnet_ids = module.vpc.private_subnet_ids

  cluster_version    = var.cluster_version
  node_instance_type = var.node_instance_type
  desired_capacity   = var.desired_capacity
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity

  endpoint_private_access        = var.cluster_endpoint_private_access
  endpoint_public_access         = var.cluster_endpoint_public_access
  public_access_cidrs            = var.cluster_endpoint_public_access_cidrs
  enabled_cluster_log_types      = var.cluster_enabled_log_types
  secrets_encryption_kms_key_arn = try(aws_kms_key.eks_secrets[0].arn, null)
  access_entries                 = var.cluster_access_entries

}
