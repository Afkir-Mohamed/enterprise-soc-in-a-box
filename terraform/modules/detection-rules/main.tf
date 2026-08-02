# ─────────────────────────────────────────────────────────────────
# DETECTION RULES MODULE
#
# Deploys:
#   1. SNS topic for alerts
#   2. IAM role for all three detection Lambdas
#   3. Three detection Lambda functions (zipped from lambdas/)
#   4. S3 event notification → EventBridge on the data lake bucket
#   5. EventBridge rule that triggers all three Lambdas on new
#      CloudTrail log delivery
#   6. Step Functions Express state machine (incident response)
# ─────────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── SNS Alert Topic ────────────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "soc-in-a-box-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── IAM role for detection Lambdas ────────────────────────────────
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "detection_lambda" {
  name               = "soc-in-a-box-detection-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "detection_lambda_policy" {
  statement {
    sid     = "ReadDataLake"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      "arn:aws:s3:::${var.data_lake_bucket_id}",
      "arn:aws:s3:::${var.data_lake_bucket_id}/cloudtrail/*",
    ]
  }
  statement {
    sid       = "StartStepFunctions"
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.incident_response.arn]
  }
  statement {
    sid       = "CloudWatchLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role_policy" "detection_lambda" {
  name   = "soc-in-a-box-detection-lambda-policy"
  role   = aws_iam_role.detection_lambda.id
  policy = data.aws_iam_policy_document.detection_lambda_policy.json
}

# ── Lambda zip packages ────────────────────────────────────────────
data "archive_file" "detect_root" {
  type        = "zip"
  source_file = "${path.module}/../../../lambdas/detect-root-activity/handler.py"
  output_path = "${path.module}/zips/detect-root-activity.zip"
}

data "archive_file" "detect_mass_iam" {
  type        = "zip"
  source_file = "${path.module}/../../../lambdas/detect-mass-iam/handler.py"
  output_path = "${path.module}/zips/detect-mass-iam.zip"
}

data "archive_file" "detect_network_recon" {
  type        = "zip"
  source_file = "${path.module}/../../../lambdas/detect-network-recon/handler.py"
  output_path = "${path.module}/zips/detect-network-recon.zip"
}

# ── Lambda functions ───────────────────────────────────────────────
resource "aws_lambda_function" "detect_root" {
  function_name    = "soc-in-a-box-detect-root-activity"
  role             = aws_iam_role.detection_lambda.arn
  filename         = data.archive_file.detect_root.output_path
  source_code_hash = data.archive_file.detect_root.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.incident_response.arn
      ENVIRONMENT       = var.environment
    }
  }
  tags = var.tags
}

resource "aws_lambda_function" "detect_mass_iam" {
  function_name    = "soc-in-a-box-detect-mass-iam"
  role             = aws_iam_role.detection_lambda.arn
  filename         = data.archive_file.detect_mass_iam.output_path
  source_code_hash = data.archive_file.detect_mass_iam.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      STATE_MACHINE_ARN    = aws_sfn_state_machine.incident_response.arn
      ENVIRONMENT          = var.environment
      IAM_WRITE_THRESHOLD  = "5"
    }
  }
  tags = var.tags
}

resource "aws_lambda_function" "detect_network_recon" {
  function_name    = "soc-in-a-box-detect-network-recon"
  role             = aws_iam_role.detection_lambda.arn
  filename         = data.archive_file.detect_network_recon.output_path
  source_code_hash = data.archive_file.detect_network_recon.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.incident_response.arn
      ENVIRONMENT       = var.environment
      ALLOWED_REGIONS   = "eu-central-1,us-east-1"
    }
  }
  tags = var.tags
}

# ── EventBridge: S3 → Lambda ───────────────────────────────────────
# Enable EventBridge notifications on the data lake bucket
resource "aws_s3_bucket_notification" "data_lake" {
  bucket      = var.data_lake_bucket_id
  eventbridge = true
}

resource "aws_cloudwatch_event_rule" "cloudtrail_delivery" {
  name        = "soc-in-a-box-cloudtrail-delivery"
  description = "Fires when a new CloudTrail log file is delivered to S3"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = { name = [var.data_lake_bucket_id] }
      object = { key = [{ prefix = "cloudtrail/AWSLogs" }] }
    }
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "detect_root" {
  rule = aws_cloudwatch_event_rule.cloudtrail_delivery.name
  arn  = aws_lambda_function.detect_root.arn
  # Transform the EventBridge event into the S3 Records format
  # the Lambda expects (same shape as direct S3 trigger)
  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
    }
    input_template = "{\"Records\":[{\"s3\":{\"bucket\":{\"name\":<bucket>},\"object\":{\"key\":<key>}}}]}"
  }
}

resource "aws_cloudwatch_event_target" "detect_mass_iam" {
  rule = aws_cloudwatch_event_rule.cloudtrail_delivery.name
  arn  = aws_lambda_function.detect_mass_iam.arn
  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
    }
    input_template = "{\"Records\":[{\"s3\":{\"bucket\":{\"name\":<bucket>},\"object\":{\"key\":<key>}}}]}"
  }
}

resource "aws_cloudwatch_event_target" "detect_network_recon" {
  rule = aws_cloudwatch_event_rule.cloudtrail_delivery.name
  arn  = aws_lambda_function.detect_network_recon.arn
  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
    }
    input_template = "{\"Records\":[{\"s3\":{\"bucket\":{\"name\":<bucket>},\"object\":{\"key\":<key>}}}]}"
  }
}

# Lambda permissions for EventBridge to invoke
resource "aws_lambda_permission" "detect_root" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.detect_root.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cloudtrail_delivery.arn
}

resource "aws_lambda_permission" "detect_mass_iam" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.detect_mass_iam.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cloudtrail_delivery.arn
}

resource "aws_lambda_permission" "detect_network_recon" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.detect_network_recon.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cloudtrail_delivery.arn
}

# ── Step Functions state machine ───────────────────────────────────
data "aws_iam_policy_document" "sfn_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn" {
  name               = "soc-in-a-box-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "sfn_policy" {
  statement {
    sid     = "PublishSNS"
    effect  = "Allow"
    actions = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
  statement {
    sid     = "RunAthenaQueries"
    effect  = "Allow"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
    ]
    resources = ["*"]
  }
  statement {
    sid     = "AthenaS3Access"
    effect  = "Allow"
    actions = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    resources = [
      "arn:aws:s3:::${var.data_lake_bucket_id}",
      "arn:aws:s3:::${var.data_lake_bucket_id}/*",
      "arn:aws:s3:::${var.athena_results_bucket_id}",
      "arn:aws:s3:::${var.athena_results_bucket_id}/*",
    ]
  }
  statement {
    sid     = "GlueForAthena"
    effect  = "Allow"
    actions = ["glue:GetTable", "glue:GetDatabase", "glue:GetPartitions"]
    resources = ["*"]
  }
  statement {
    sid     = "WriteIncidentRecord"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.data_lake_bucket_id}/incidents/*"]
  }
  statement {
    sid     = "CloudWatchLogs"
    effect  = "Allow"
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:CreateLogDelivery", "logs:DescribeLogGroups"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "sfn" {
  name   = "soc-in-a-box-sfn-policy"
  role   = aws_iam_role.sfn.id
  policy = data.aws_iam_policy_document.sfn_policy.json
}

resource "aws_sfn_state_machine" "incident_response" {
  name     = "soc-in-a-box-incident-response"
  role_arn = aws_iam_role.sfn.arn
  # Express workflows: 100k free executions/month, ideal for
  # high-volume event-driven response automation
  type       = "EXPRESS"
  definition = replace(
    replace(
      replace(
        file("${path.module}/../../../step-functions/incident-response.asl.json"),
        "SNS_TOPIC_ARN_PLACEHOLDER", aws_sns_topic.alerts.arn
      ),
      "DATA_LAKE_BUCKET_PLACEHOLDER", var.data_lake_bucket_id
    ),
    "ATHENA_RESULTS_BUCKET_PLACEHOLDER", var.athena_results_bucket_id
  )
  tags = var.tags
}
