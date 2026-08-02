variable "aws_region" {
  description = "AWS region for the state bucket/lock table. Should match the region you'll deploy the main stack into."
  type        = string
  default     = "eu-central-1"
}

variable "github_oidc_enabled" {
  description = "Set true to create the GitHub Actions OIDC provider + IAM role for CI/CD"
  type        = bool
  default     = false
}

variable "github_repo" {
  description = "Your GitHub repo in 'owner/repo-name' format, used to scope the OIDC trust policy"
  type        = string
  default     = "REPLACE_ME/enterprise-soc-in-a-box"
}
