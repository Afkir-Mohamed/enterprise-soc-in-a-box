variable "data_lake_bucket_id" {
  description = "S3 data lake bucket name"
  type        = string
}

variable "athena_results_bucket_id" {
  description = "S3 Athena results bucket name"
  type        = string
}

variable "glue_database_name" {
  description = "Glue database name for Athena queries in Step Functions"
  type        = string
}

variable "alert_email" {
  description = "Email address for SNS alert notifications (leave empty to skip)"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
  default     = "dev"
}

variable "tags" {
  type    = map(string)
  default = {}
}
