# ─────────────────────────────────────────────────────────────────
# GITHUB ACTIONS OIDC — lets your terraform.yml workflow assume an
# AWS role WITHOUT storing an AWS access key as a GitHub secret.
# This is the piece that makes "AWS_GHA_ROLE_ARN" in the workflow
# real. Enable it by setting github_oidc_enabled = true and filling
# in your repo (see variables.tf).
#
# After apply, put the role_arn output into your GitHub repo secret
# AWS_GHA_ROLE_ARN.
# ─────────────────────────────────────────────────────────────────

resource "aws_iam_openid_connect_provider" "github" {
  count = var.github_oidc_enabled ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] # GitHub's OIDC thumbprint, current as of Free Tier docs
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  count = var.github_oidc_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Restrict to a specific repo + branch pattern so a fork or
    # unrelated repo can't assume this role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  count              = var.github_oidc_enabled ? 1 : 0
  name               = "soc-in-a-box-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role[0].json
}

# Scope this down further once Phase 3+ Lambdas/Step Functions
# exist — for Phase 1 it needs S3, CloudTrail, EC2/VPC, and Glue.
resource "aws_iam_role_policy_attachment" "github_actions_poweruser" {
  count      = var.github_oidc_enabled ? 1 : 0
  role       = aws_iam_role.github_actions[0].name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

output "github_actions_role_arn" {
  value       = var.github_oidc_enabled ? aws_iam_role.github_actions[0].arn : null
  description = "Put this in the GitHub repo secret AWS_GHA_ROLE_ARN"
}
