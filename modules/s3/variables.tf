variable "bucket_name" {
  description = "Globally unique bucket name"
  type        = string
}

variable "allowed_principal_arns" {
  description = "IAM ARNs allowed to access the bucket. Empty list = no principal restriction."
  type        = list(string)
  default     = []
}

variable "force_destroy" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}