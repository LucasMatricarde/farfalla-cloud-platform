# Values supplied at init: terraform init -backend-config=...
# bucket/dynamodb_table created by terraform/state-backend (Task 2).
terraform {
  backend "s3" {
    key     = "prod/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
