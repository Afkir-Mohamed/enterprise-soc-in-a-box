# ─────────────────────────────────────────────────────────────────
# ATHENA QUERIES MODULE
#
# Four things happen here:
#   1. A dedicated S3 bucket for Athena query results (Athena
#      requires a result location before it can run any query)
#   2. An Athena workgroup scoped to this project, with a per-query
#      data scanned limit (safety net against runaway scans eating
#      into the 1 TB/month Free Tier allowance)
#   3. An IAM role that Glue Crawlers assume to read the data lake
#      and write table definitions into the Glue Catalog
#   4. Two Glue Crawlers — one for CloudTrail (JSON), one for VPC
#      Flow Logs (Parquet) — that auto-discover the schema and
#      register queryable tables in the Glue database
# ─────────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Athena query results bucket ────────────────────────────────────
# Athena writes every query's result as a CSV here. This is separate
# from the data lake bucket on purpose — mixing query output with
# source logs makes lifecycle management messy.
resource "aws_s3_bucket" "athena_results" {
  bucket = var.athena_results_bucket_name
  tags   = merge(var.tags, { Purpose = "athena-query-results" })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Query results don't need to live long — 30 days is plenty for a lab.
resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  rule {
    id     = "expire-results"
    status = "Enabled"
    filter { prefix = "" }
    expiration { days = 30 }
  }
}

# ── Athena workgroup ───────────────────────────────────────────────
# A workgroup is a logical boundary for Athena queries — it controls
# where results go and sets guardrails. The 1 GB per-query scan limit
# is a safety net: if you accidentally write a query that would scan
# the entire data lake, it gets cancelled before it eats your Free
# Tier allowance. Raise it intentionally if a specific query needs more.
resource "aws_athena_workgroup" "soc" {
  name        = var.athena_workgroup_name
  description = "SOC-in-a-Box threat hunting workgroup"
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = false # no CloudWatch cost

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    bytes_scanned_cutoff_per_query = 1073741824 # 1 GB hard limit per query
  }

  tags = var.tags
}

# ── IAM role for Glue Crawlers ─────────────────────────────────────
# Glue Crawlers need to: read the data lake bucket, write table
# definitions to the Glue Catalog, and write crawler logs to
# CloudWatch (Glue does this automatically; you can't disable it,
# but the log volume is tiny).
data "aws_iam_policy_document" "glue_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue_crawler" {
  name               = "soc-in-a-box-glue-crawler"
  assume_role_policy = data.aws_iam_policy_document.glue_assume_role.json
  tags               = var.tags
}

# AWS managed policy that gives Glue the baseline permissions it
# needs (CloudWatch Logs, Glue Catalog reads/writes, S3 GetObject
# on specific prefixes — we restrict that further below).
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Scoped S3 read — only the two prefixes the crawlers need to read.
# The managed policy above grants broad S3 access which we narrow
# with this inline policy.
data "aws_iam_policy_document" "glue_s3_read" {
  statement {
    sid    = "ReadDataLakePrefixes"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.data_lake_bucket_id}",
      "arn:aws:s3:::${var.data_lake_bucket_id}/cloudtrail/*",
      "arn:aws:s3:::${var.data_lake_bucket_id}/vpc-flow-logs/*",
    ]
  }
}

resource "aws_iam_role_policy" "glue_s3_read" {
  name   = "soc-in-a-box-glue-s3-read"
  role   = aws_iam_role.glue_crawler.id
  policy = data.aws_iam_policy_document.glue_s3_read.json
}

# ── Glue Crawler: CloudTrail ───────────────────────────────────────
# Crawls the cloudtrail/ prefix, detects the nested JSON schema
# (eventVersion, eventTime, eventSource, eventName, userIdentity,
# requestParameters, responseElements, etc.) and registers a table
# called "cloudtrail" in the Glue database.
#
# Schedule: daily at 01:00 UTC. CloudTrail delivers logs every
# ~10 minutes but we only need the catalog updated once a day for
# threat hunting — on-demand crawls are always available in the
# AWS console if you need to refresh sooner.
resource "aws_glue_crawler" "cloudtrail" {
  name          = "soc-in-a-box-cloudtrail-crawler"
  role          = aws_iam_role.glue_crawler.arn
  database_name = var.glue_database_name
  description   = "Crawls CloudTrail JSON logs and registers/updates the cloudtrail table"
  schedule      = "cron(0 1 * * ? *)"

  s3_target {
    path = "s3://${var.data_lake_bucket_id}/cloudtrail/AWSLogs/${data.aws_caller_identity.current.account_id}/CloudTrail/"
    # Tell the crawler to skip the CloudTrail digest files — they're
    # integrity-check files, not event logs, and have a different schema.
    exclusions = [
      "**.digest/**",
      "**CloudTrail-Digest**",
    ]
  }

  schema_change_policy {
    delete_behavior = "LOG"   # don't drop the table if a field disappears
    update_behavior = "UPDATE_IN_DATABASE" # add new fields automatically
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })

  tags = var.tags
}

# ── Glue Crawler: VPC Flow Logs ────────────────────────────────────
# Crawls the vpc-flow-logs/ prefix. Because we configured Flow Logs
# to write Parquet (not plain text), Glue can read column types
# directly from the file metadata — no manual schema definition needed.
resource "aws_glue_crawler" "vpc_flow_logs" {
  name          = "soc-in-a-box-flowlogs-crawler"
  role          = aws_iam_role.glue_crawler.arn
  database_name = var.glue_database_name
  description   = "Crawls VPC Flow Log Parquet files and registers/updates the vpc_flow_logs table"
  schedule      = "cron(0 1 * * ? *)"

  s3_target {
    path = "s3://${var.data_lake_bucket_id}/vpc-flow-logs/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
  })

  tags = var.tags
}
