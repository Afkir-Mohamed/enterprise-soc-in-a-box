variable "aws_region" {
  description = "AWS region to deploy the SOC-in-a-Box stack into"
  type        = string
  default     = "eu-west-1"
}

variable "data_lake_bucket_name" {
  description = "Globally-unique name for the security data lake S3 bucket (e.g. soc-in-a-box-<yourname>-dev)"
  type        = string
}

variable "glue_database_name" {
  description = "Glue Catalog database name used by Athena"
  type        = string
  default     = "soc_in_a_box"
}

variable "athena_results_bucket_name" {
  description = "Globally-unique S3 bucket name for Athena query results (e.g. soc-in-a-box-athena-<account-id>)"
  type        = string
}

variable "alert_email" {
  description = "Email address to receive SNS security alerts (leave empty to skip)"
  type        = string
  default     = ""
}
