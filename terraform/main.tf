terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

module "network" {
  source       = "./modules/network"
  project_name = var.project_name
}

module "container_env" {
  source        = "./modules/container_env"
  project_name  = var.project_name
  vpc_id        = module.network.vpc_id
  public_subnets = module.network.public_subnet_ids
  # valfri SSH-nyckel om du vill ansluta via SSH
  # key_name     = "my-key-pair"
}

