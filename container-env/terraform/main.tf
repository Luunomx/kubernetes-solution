################################################
# Terraform & Providers
################################################
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::878311921064:role/EKSAdminRole"
  }
}

################################################
# VPC
################################################
module "vpc" {
  source = "./modules/vpc"

  name                  = var.name
  vpc_cidr              = var.vpc_cidr
  subnet_a_cidr         = var.subnet_a_cidr
  subnet_b_cidr         = var.subnet_b_cidr
  private_subnet_a_cidr = var.private_subnet_a_cidr
  private_subnet_b_cidr = var.private_subnet_b_cidr
}

################################################
# IAM
################################################
module "iam" {
  source = "./modules/iam"
  name   = var.name
}

################################################
# Security Groups
################################################
module "security-group" {
  source = "./modules/security-group"

  name   = var.name
  vpc_id = module.vpc.vpc_id
}

################################################
# EKS Cluster
################################################
module "eks" {
  source = "./modules/eks"

  name       = var.name
  region     = var.region
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  cluster_version    = "1.30"
  node_instance_type = "t3.medium"
  desired_capacity   = 2
  max_capacity       = 3
  min_capacity       = 1

  sg_ids           = [module.security-group.alb_sg_id]
  instance_profile = module.iam.instance_profile_name
}

################################################
# Application Load Balancer (EKS)
################################################
module "alb" {
  source = "./modules/alb"

  name       = var.name
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids
  sg_id      = module.security-group.alb_sg_id
}

################################################
# Elastic Container Registry
################################################
module "ecr" {
  source = "./modules/ecr"
}

