output "bucket_id" {
  value = aws_s3_bucket.data_lake.id
}

output "bucket_arn" {
  value = aws_s3_bucket.data_lake.arn
}

output "glue_database_name" {
  value = aws_glue_catalog_database.security_lake.name
}
