variable "vpc_cidr" {
  description = "CIDR block for the lab VPC"
  type        = string
  default     = "10.42.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.42.1.0/24"
}

variable "private_subnet_cidr" {
  type    = string
  default = "10.42.2.0/24"
}

variable "data_lake_bucket_id" {
  description = "S3 bucket ID (name) from the s3-data-lake module — CloudTrail needs the bare name"
  type        = string
}

variable "data_lake_bucket_arn" {
  description = "S3 bucket ARN from the s3-data-lake module — VPC Flow Logs destination needs the ARN"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
