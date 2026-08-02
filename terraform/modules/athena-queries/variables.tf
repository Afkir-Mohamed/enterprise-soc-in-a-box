variable "data_lake_bucket_id" {
  description = "Name (ID) of the S3 data lake bucket — used to scope Glue crawler S3 targets and IAM policy"
  type        = string
}

variable "glue_database_name" {
  description = "Glue Catalog database name — crawlers register tables here"
  type        = string
}

variable "athena_results_bucket_name" {
  description = "Globally-unique S3 bucket name for Athena query results"
  type        = string
}

variable "athena_workgroup_name" {
  description = "Name of the Athena workgroup"
  type        = string
  default     = "soc-in-a-box"
}

variable "tags" {
  type    = map(string)
  default = {}
}
