terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Local state on purpose: this stack creates the remote backend
}

provider "aws" {
  region = var.region
}

module "state_bucket" {
  source                 = "../modules/s3"
  bucket_name            = var.state_bucket_name
  allowed_principal_arns = var.bucket_allowed_principal_arns
  tags                   = { Purpose = "terraform-state" }
}

# Least-privilege policy for state access
data "aws_iam_policy_document" "state_access" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = [module.state_bucket.bucket_arn]
  }
  statement {
    sid       = "ReadWriteStateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"] # Delete needed for .tflock lock files
    resources = ["${module.state_bucket.bucket_arn}/*"]
  }
}

resource "aws_iam_policy" "state_access" {
  name   = "terraform-state-access"
  policy = data.aws_iam_policy_document.state_access.json
}

resource "aws_iam_group" "state_users" {
  name = "terraform-state-users"
}

resource "aws_iam_group_policy_attachment" "state_access" {
  group      = aws_iam_group.state_users.name
  policy_arn = aws_iam_policy.state_access.arn
}

resource "aws_iam_group_membership" "state_users" {
  count = length(var.state_users) > 0 ? 1 : 0
  name  = "terraform-state-users-membership"
  group = aws_iam_group.state_users.name
  users = var.state_users
}