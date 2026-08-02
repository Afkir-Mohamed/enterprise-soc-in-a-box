# ─────────────────────────────────────────────────────────────────
# BOOTSTRAP — run this once, manually, before touching terraform/
#
# Why this exists as a separate config:
# Terraform can't create the S3 bucket + DynamoDB table it will use
# for its OWN remote state in the same apply that configures that
# backend (chicken-and-egg problem). So this tiny config uses plain
# local state to create just those two resources. After this runs,
# terraform/environments/dev points at the bucket/table created here
# and never touches local state again.
#
# Usage:
#   cd bootstrap
#   terraform init
#   terraform apply
#   (note the bucket_name and table_name outputs, they go into
#    terraform/environments/dev/backend.tf)
# ─────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Random suffix keeps the bucket name globally unique without you
# having to pick one — S3 bucket names are a global namespace.
resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "tf_state" {
  bucket = "soc-in-a-box-tfstate-${random_id.suffix.hex}"

  # Free tier note: this bucket holds only Terraform state (KBs of
  # JSON), nowhere close to the 5 GB Free Tier S3 allowance.
  tags = {
    Project   = "enterprise-soc-in-a-box"
    Purpose   = "terraform-remote-state"
    ManagedBy = "terraform-bootstrap"
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled" # lets you recover a previous state file if an apply goes wrong
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3, free — see ARCHITECTURE.md for the KMS trade-off discussion
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for state locking (prevents two people/pipelines
# from running apply at once and corrupting state). On-demand
# billing mode means you pay per request, not per hour — at this
# scale (a handful of applies a week) it's effectively $0.
resource "aws_dynamodb_table" "tf_lock" {
  name         = "soc-in-a-box-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project   = "enterprise-soc-in-a-box"
    Purpose   = "terraform-state-locking"
    ManagedBy = "terraform-bootstrap"
  }
}
