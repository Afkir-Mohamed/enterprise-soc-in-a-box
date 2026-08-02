variable "bucket_name" {
  description = "Globally-unique S3 bucket name for the security data lake"
  type        = string
}

variable "glue_database_name" {
  description = "Name of the Glue Catalog database for Athena queries"
  type        = string
  default     = "soc_in_a_box"
}

variable "tags" {
  description = "Common tags applied to all resources in this module"
  type        = map(string)
  default     = {}
}
