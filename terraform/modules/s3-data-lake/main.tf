# ─────────────────────────────────────────────────────────────────
# S3 DATA LAKE MODULE
#
# One bucket, two prefixes, one Glue database. Every log source in
# this project lands here:
#   s3://<bucket>/cloudtrail/AWSLogs/<account-id>/CloudTrail/<region>/<yyyy>/<mm>/<dd>/
#   s3://<bucket>/vpc-flow-logs/AWSLogs/<account-id>/vpcflowlogs/<region>/<yyyy>/<mm>/<dd>/
#
# Those prefix layouts are fixed by AWS (CloudTrail and VPC Flow
# Logs both write Hive-style date partitions automatically when you
# point them at S3) — Athena/Glue just need to know the partition
# scheme, which is handled by the Glue Crawlers in Phase 2.
# ─────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "data_lake" {
  bucket = var.bucket_name

  tags = merge(var.tags, {
    Purpose = "security-data-lake"
  })
}

# SSE-S3 (AES256), not KMS.
# Why: KMS is $1/month per key + per-request charges. SSE-S3 is
# free and, for a lab project with no compliance mandate, gives you
# encryption-at-rest without a recurring cost. See ARCHITECTURE.md
# for the documented trade-off (call out KMS + Object Lock as the
# production-grade upgrade path).
resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket                  = aws_s3_bucket.data_lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: move logs to Glacier after 90 days to keep long-term
# storage costs near zero once you're past the 5 GB Free Tier
# allowance for S3 Standard. Nothing is deleted — this is a lab,
# but the pattern mirrors what you'd defend in an interview
# (log retention vs. cost).
resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id     = "cloudtrail-to-glacier"
    status = "Enabled"
    filter {
      prefix = "cloudtrail/"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }

  rule {
    id     = "flow-logs-to-glacier"
    status = "Enabled"
    filter {
      prefix = "vpc-flow-logs/"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# Bucket policy: allow CloudTrail and VPC Flow Logs delivery
# services to write into their respective prefixes only, each
# scoped with an aws:SourceAccount / aws:SourceArn condition so
# only *your* trail/flow-log can write here (not anyone else's).
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "data_lake_bucket_policy" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.data_lake.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.data_lake.arn}/cloudtrail/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AWSLogDeliveryFlowLogsWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.data_lake.arn}/vpc-flow-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AWSLogDeliveryAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.data_lake.arn]
  }
}

resource "aws_s3_bucket_policy" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  policy = data.aws_iam_policy_document.data_lake_bucket_policy.json
}

# Glue Catalog database — the "schema registry" Athena queries
# against. Tables get added by Glue Crawlers in Phase 2; the
# database itself is foundational so it exists from day one.
resource "aws_glue_catalog_database" "security_lake" {
  name        = var.glue_database_name
  description = "Security data lake catalog: CloudTrail + VPC Flow Logs for SOC-in-a-Box"
}
