# Terraform Modular Infrastructure with S3 Remote State

A modular Terraform project that provisions an AWS VPC across multiple
environments (dev / prod) and stores state centrally in a versioned,
access-controlled S3 bucket.

## Architecture

```
┌──────────────────────┐
│  bootstrap/          │  local state, run once
│  ├─ S3 module        │──► S3 bucket (versioned, encrypted, private)
│  └─ IAM group/policy │──► least-privilege access to state objects
└──────────────────────┘
            │ bucket
            ▼
┌──────────────────────┐        ┌──────────────────────┐
│  envs/dev            │        │  envs/prod           │
│  key: dev/....tfstate│        │  key: prod/...tfstate│
│  └─ VPC module       │        │  └─ VPC module       │
└──────────────────────┘        └──────────────────────┘
```

Each VPC contains:
- A VPC with DNS support and hostnames enabled
- Public subnets (auto-assign public IP) routed to an Internet Gateway
- Private subnets with their own route table and no internet route
- Subnets spread across availability zones

### Why a bootstrap stack?
The state bucket cannot store its own state before it exists. `bootstrap/`
creates the bucket using local state; the environments then use that bucket
as their remote backend.

## Repository Structure

```
.
├── bootstrap/        # state bucket + IAM access (local state)
├── modules/
│   ├── vpc/          # reusable networking module
│   └── s3/           # reusable versioned S3 bucket module
└── envs/
    ├── dev/          # dev root configuration + dev.tfvars
    └── prod/         # prod root configuration + prod.tfvars
```

## Prerequisites
- Terraform >= 1.10 (required for S3-native state locking)
- AWS CLI configured with permissions for VPC, S3 and IAM
- An AWS account

## Getting Started

### 1. Create the remote backend bucket
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export BUCKET="tfstate-${ACCOUNT_ID}-assessment"

cd bootstrap
terraform init
terraform apply -var="state_bucket_name=$BUCKET"
```

### 2. Configure the backend in each environment
Backend blocks cannot use variables, so set the bucket name in
`envs/<env>/backend.tf`:
```bash
sed -i "s/YOUR-UNIQUE-STATE-BUCKET/$BUCKET/" envs/dev/backend.tf envs/prod/backend.tf
```

### 3. Deploy an environment
```bash
cd envs/dev
terraform init                       # connects to the S3 backend
terraform plan  -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

### 4. Deploy another environment
```bash
cd envs/prod
terraform init
terraform apply -var-file=prod.tfvars
```

### Migrating existing local state
If an environment already has local state, add the `backend "s3"` block and run:
```bash
terraform init -migrate-state
```

## State Management
- **Storage:** S3 bucket with versioning, so a corrupted or overwritten state
  file can be restored from a previous version.
- **Isolation:** each environment uses its own key (`dev/terraform.tfstate`,
  `prod/terraform.tfstate`).
- **Locking:** `use_lockfile = true` creates a `.tflock` object in S3 to prevent
  concurrent runs.
- **Encryption:** AES-256 server-side encryption and `encrypt = true` in the backend.

## Access Control
| Layer | Control |
|-------|---------|
| Bucket | Public access fully blocked |
| Bucket policy | Denies all non-TLS requests; optionally denies any principal not in `bucket_allowed_principal_arns` |
| IAM policy | `terraform-state-access`: `ListBucket` on the bucket; `Get/Put/DeleteObject` on objects (Delete is needed to release lock files) |
| IAM group | `terraform-state-users` has the policy attached; add users via `state_users` |

> If you set `bucket_allowed_principal_arns`, include your own admin ARN to
> avoid locking yourself out.

## Inputs

### VPC module (`modules/vpc`)
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `name` | string | n/a | Name prefix for resources |
| `vpc_cidr` | string | n/a | VPC CIDR block |
| `public_subnet_cidrs` | list(string) | n/a | Public subnet CIDRs (one per AZ) |
| `private_subnet_cidrs` | list(string) | n/a | Private subnet CIDRs (one per AZ) |
| `azs` | list(string) | n/a | Availability zones, matched by index |
| `tags` | map(string) | `{}` | Extra tags |

### S3 module (`modules/s3`)
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `bucket_name` | string | n/a | Globally unique bucket name |
| `allowed_principal_arns` | list(string) | `[]` | Principals allowed access (empty = no restriction) |
| `force_destroy` | bool | `false` | Allow destroying a non-empty bucket |
| `tags` | map(string) | `{}` | Extra tags |

### Bootstrap (`bootstrap`)
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `region` | string | `us-east-1` | AWS region |
| `state_bucket_name` | string | n/a | State bucket name |
| `state_users` | list(string) | `[]` | IAM users added to the state-access group |
| `bucket_allowed_principal_arns` | list(string) | `[]` | Bucket-level allow-list |

### Environments (`envs/*`)
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `region` | string | `us-east-1` | AWS region |
| `environment` | string | n/a | Environment name (dev, prod) |
| `vpc_cidr` | string | n/a | VPC CIDR |
| `public_subnet_cidrs` | list(string) | n/a | Public subnet CIDRs |
| `private_subnet_cidrs` | list(string) | n/a | Private subnet CIDRs |
| `az_count` | number | `2` | Number of AZs to use |

## Outputs

| Output | Source | Description |
|--------|--------|-------------|
| `vpc_id` | env / vpc module | ID of the VPC |
| `public_subnet_ids` | env / vpc module | Public subnet IDs |
| `private_subnet_ids` | env / vpc module | Private subnet IDs |
| `internet_gateway_id` | vpc module | Internet gateway ID |
| `bucket_id` / `bucket_arn` | s3 module | State bucket name and ARN |
| `state_bucket_name` | bootstrap | State bucket name |
| `state_access_policy_arn` | bootstrap | ARN of the state-access IAM policy |

## Environment Separation
The same modules are reused, and only variable values change:

| Setting | dev | prod |
|---------|-----|------|
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 |
| AZs | 2 | 3 |
| Public subnets | 2 | 3 |
| Private subnets | 2 | 3 |
| State key | `dev/terraform.tfstate` | `prod/terraform.tfstate` |

## Verification
Screenshots are in `docs/screenshots/`:
- `01-backend-init.png`: successful S3 backend initialization
- `02-state-in-s3.png`: state objects in the bucket
- `03-bucket-versioning.png`: versioning enabled
- `04-vpcs.png`: dev and prod VPCs in the console
- `05-subnets-routing.png`: subnets, route tables and IGW

## Cleanup
```bash
cd envs/prod && terraform destroy -var-file=prod.tfvars
cd ../dev    && terraform destroy -var-file=dev.tfvars
cd ../../bootstrap && terraform destroy -var="state_bucket_name=$BUCKET"
```
The state bucket is versioned, so empty all object versions (or set
`force_destroy = true`) before destroying the bootstrap stack.

## Design Notes and Possible Improvements
- A NAT gateway can be added for private subnet egress; it is omitted to keep costs at zero.
- KMS encryption could replace AES-256 for stricter compliance.
- A CI pipeline (`terraform fmt`, `validate`, `plan`) could run on pull requests.