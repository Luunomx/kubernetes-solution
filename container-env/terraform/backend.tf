terraform {
  backend "s3" {
    bucket         = "assignment2-terraform-state"
    key            = "container-env/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
