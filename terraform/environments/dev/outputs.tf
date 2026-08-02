output "data_lake_bucket" {
  value = module.s3_data_lake.bucket_id
}

output "glue_database" {
  value = module.s3_data_lake.glue_database_name
}

output "vpc_id" {
  value = module.log_sources.vpc_id
}

output "cloudtrail_arn" {
  value = module.log_sources.cloudtrail_arn
}

output "athena_workgroup" {
  value = module.athena_queries.athena_workgroup_name
}

output "athena_results_bucket" {
  value = module.athena_queries.athena_results_bucket
}
