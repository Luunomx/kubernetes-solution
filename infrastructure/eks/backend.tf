terraform {
  backend "s3" {
    key     = "infrastructure/eks/terraform.tfstate"
    encrypt = true
  }
}
