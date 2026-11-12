output "state_bucket_name" {
  value = module.state_bucket.bucket_id
}

output "state_access_policy_arn" {
  value = aws_iam_policy.state_access.arn
}