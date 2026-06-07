terraform {
  backend "s3" {
    bucket         = "quantamvector-infra-statefile-backup-kunal-2026"
    key            = "quantamvector/2-eks/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "quantamvector-terraform-locks"
    encrypt        = true
  }
}