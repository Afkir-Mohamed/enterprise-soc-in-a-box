# Fill these in with the outputs from `bootstrap/` after you run it once:
#   terraform -chdir=bootstrap output state_bucket_name
#   terraform -chdir=bootstrap output state_lock_table_name
terraform {
  backend "s3" {
    bucket         = "soc-in-a-box-tfstate-7b2b6b9c"
    key            = "soc-in-a-box/dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "soc-in-a-box-tfstate-lock"
    encrypt        = true
  }
}
