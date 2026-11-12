provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source               = "../../modules/vpc"
  name                 = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  azs                  = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  tags                 = { Environment = var.environment, ManagedBy = "terraform" }
}