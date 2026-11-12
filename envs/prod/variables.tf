variable "region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "az_count" {
  type    = number
  default = 2
}