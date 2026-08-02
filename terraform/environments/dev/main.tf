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
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project     = "enterprise-soc-in-a-box"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

# ── Phase 1: foundation ─────────────────────────────────────────
module "s3_data_lake" {
  source = "../../modules/s3-data-lake"

  bucket_name        = var.data_lake_bucket_name
  glue_database_name = var.glue_database_name
  tags               = local.common_tags
}

module "log_sources" {
  source = "../../modules/log-sources"

  data_lake_bucket_id  = module.s3_data_lake.bucket_id
  data_lake_bucket_arn = module.s3_data_lake.bucket_arn
  tags                 = local.common_tags

  # CloudTrail must be able to write to the bucket before the trail
  # is created — the bucket policy has to exist first.
  depends_on = [module.s3_data_lake]
}

# ── Phase 2: Glue crawlers + Athena workgroup ───────────────────
module "athena_queries" {
  source = "../../modules/athena-queries"

  data_lake_bucket_id        = module.s3_data_lake.bucket_id
  glue_database_name         = module.s3_data_lake.glue_database_name
  athena_results_bucket_name = var.athena_results_bucket_name
  athena_workgroup_name      = "soc-in-a-box"
  tags                       = local.common_tags

  depends_on = [module.s3_data_lake]
}

# ── Phase 3: Detection Lambdas + Step Functions ─────────────────
module "detection_rules" {
  source = "../../modules/detection-rules"

  data_lake_bucket_id      = module.s3_data_lake.bucket_id
  athena_results_bucket_id = module.athena_queries.athena_results_bucket
  glue_database_name       = module.s3_data_lake.glue_database_name
  alert_email              = var.alert_email
  environment              = "dev"
  tags                     = local.common_tags

  depends_on = [module.s3_data_lake, module.athena_queries]
}
