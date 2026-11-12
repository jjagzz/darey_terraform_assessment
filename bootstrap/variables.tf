variable "region" {
  type    = string
  default = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally unique name for the state bucket"
  type        = string
}

variable "state_users" {
  description = "IAM usernames allowed to read/write state"
  type        = list(string)
  default     = []
}

variable "bucket_allowed_principal_arns" {
  description = "Optional bucket-level allow-list. Include your own admin ARN to avoid lockout."
  type        = list(string)
  default     = []
}