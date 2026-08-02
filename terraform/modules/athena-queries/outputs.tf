output "athena_workgroup_name" {
  value = aws_athena_workgroup.soc.name
}

output "athena_results_bucket" {
  value = aws_s3_bucket.athena_results.id
}

output "cloudtrail_crawler_name" {
  value = aws_glue_crawler.cloudtrail.name
}

output "flowlogs_crawler_name" {
  value = aws_glue_crawler.vpc_flow_logs.name
}

output "glue_crawler_role_arn" {
  value = aws_iam_role.glue_crawler.arn
}
