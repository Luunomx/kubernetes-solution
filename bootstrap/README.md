# Terraform backend bootstrap

This configuration creates the S3 bucket and DynamoDB table used for Terraform state. Supply names for your own AWS account; no environment-specific names are committed.

```sh
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform validate
terraform plan
```

Review the plan before applying it. The copied `terraform.tfvars` file is ignored by Git.
