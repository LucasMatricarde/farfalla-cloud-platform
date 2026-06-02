# DevOps GitOps Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a complete, deployable DevOps repo that runs the existing ERP-Farfalla app on AWS via k3s/EC2, RDS, ArgoCD GitOps, GitHub Actions CI/CD, and Prometheus/Grafana/Loki observability — **all infrastructure-as-code, no `terraform apply` performed by the implementer** (operator deploys with their own AWS creds).

**Architecture:** Terraform (modular) provisions VPC + EC2 (k3s, built-in Traefik) + RDS Postgres + ECR + S3/DynamoDB state + GitHub OIDC IAM. ArgoCD (app-of-apps) syncs platform charts (cert-manager, kube-prometheus-stack, Loki) and the Farfalla app from `k8s/`. GitHub Actions validates infra on PR, builds/pushes images from the ERP-Farfalla repo and bumps the GitOps image tag on merge. Public access via `*.sslip.io` + Let's Encrypt TLS.

**Tech Stack:** Terraform, AWS (VPC/EC2/RDS/ECR/IAM/S3/DynamoDB), k3s, Traefik, cert-manager, ArgoCD, Kustomize, kube-prometheus-stack, Loki, GitHub Actions (OIDC).

**App repo (built by CD, not modified here):** `/Users/lucasmatricarde/ProjetosPessoais/ERP-Farfalla` — `backend/Dockerfile` target `prod` (port 8080, `/actuator/health`, `/actuator/prometheus`), `frontend/Dockerfile` (nginx serving Angular). Public GitHub ref assumed `lucas.../erp-farfalla` (operator sets `APP_REPO` var).

**Validation tooling (install via `brew` if missing):** `terraform`, `kustomize`, `kubeconform`, `actionlint`, `shellcheck`, `yamllint`. Infra has no unit-test framework; the "test" gate per task is **format + static validation** (the IaC analog of a failing/passing test). No AWS calls.

---

## File Structure

```
Cloud/
  .gitignore                      # tf/node/os junk
  README.md                       # project overview + deploy quickstart
  terraform/
    state-backend/                # standalone root, LOCAL state, applied first
      main.tf  variables.tf  outputs.tf  versions.tf
    modules/
      network/  {main.tf,variables.tf,outputs.tf}     # VPC, subnets, IGW, routes, SGs
      ecr/      {main.tf,variables.tf,outputs.tf}     # 2 repos
      rds/      {main.tf,variables.tf,outputs.tf}     # Postgres free tier
      ec2-k3s/  {main.tf,variables.tf,outputs.tf,user_data.sh.tftpl}
    envs/prod/  {versions.tf,backend.tf,main.tf,variables.tf,outputs.tf,terraform.tfvars.example}
  k8s/
    bootstrap/   {project.yaml, app-of-apps.yaml}
    platform/
      cert-manager/          {application.yaml, cluster-issuer.yaml}
      kube-prometheus-stack/ {application.yaml}
      loki/                  {application.yaml}
    apps/farfalla/
      kustomization.yaml
      namespace.yaml
      backend-deployment.yaml  backend-service.yaml  backend-servicemonitor.yaml
      backend-config.yaml      backend-secret.example.yaml
      frontend-deployment.yaml frontend-service.yaml
      ingressroute.yaml        certificate.yaml
  .github/workflows/  {ci.yml, cd.yml}
  scripts/  {bootstrap-cluster.sh, install-argocd.sh, fetch-kubeconfig.sh}
  docs/
    architecture.md  runbook.md
    superpowers/plans/2026-06-01-devops-gitops-platform.md  (this file)
```

**Conventions used across tasks:** AWS region `us-east-1`. Project prefix `farfalla`. Namespaces: `argocd`, `cert-manager`, `monitoring`, `farfalla`. Domain host pattern `app.<EIP>.sslip.io` / `grafana.<EIP>.sslip.io` (EIP substituted at deploy time). Terraform `>= 1.7`, AWS provider `~> 5.0`.

---

## Task 1: Repo scaffolding (.gitignore + README skeleton)

**Files:**
- Create: `.gitignore`
- Create: `README.md`

- [ ] **Step 1: Create `.gitignore`**

```gitignore
# Terraform
**/.terraform/*
*.tfstate
*.tfstate.*
crash.log
*.tfvars
!*.tfvars.example
.terraform.lock.hcl

# Node / Angular (only if building locally)
node_modules/
dist/

# Secrets / kube
kubeconfig
*.kubeconfig
k8s/**/secret.yaml
!k8s/**/secret.example.yaml

# OS / editor
.DS_Store
.idea/
*.swp
```

- [ ] **Step 2: Create `README.md` skeleton**

```markdown
# Farfalla Cloud Platform

GitOps deployment of the ERP-Farfalla app on AWS (k3s + ArgoCD), provisioned with Terraform, delivered by GitHub Actions, observed with Prometheus/Grafana/Loki.

## Pillars
- **IaC:** Terraform — VPC, EC2/k3s, RDS, ECR, S3/DynamoDB state, GitHub OIDC.
- **K8s:** k3s on a single EC2, Traefik ingress, cert-manager TLS.
- **CI/CD:** GitHub Actions — infra validation on PR; build→ECR + GitOps tag bump on merge.
- **GitOps:** ArgoCD app-of-apps.
- **Observability:** kube-prometheus-stack + Loki.

## Deploy quickstart
See `docs/runbook.md`. Architecture in `docs/architecture.md`.

> v1 scope: single node, single env. Future: EKS, multi-env, autoscaling, Datadog, canary.
```

- [ ] **Step 3: Verify files exist**

Run: `ls -1 .gitignore README.md`
Expected: both listed, no error.

- [ ] **Step 4: Commit**

```bash
git add .gitignore README.md
git commit -m "chore: scaffold repo with gitignore and README"
```

---

## Task 2: Terraform state backend (S3 + DynamoDB, standalone)

**Files:**
- Create: `terraform/state-backend/versions.tf`
- Create: `terraform/state-backend/variables.tf`
- Create: `terraform/state-backend/main.tf`
- Create: `terraform/state-backend/outputs.tf`

- [ ] **Step 1: `versions.tf`**

```hcl
terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}
```

- [ ] **Step 2: `variables.tf`**

```hcl
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform state"
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB table for state locking"
  type        = string
  default     = "farfalla-tf-locks"
}
```

- [ ] **Step 3: `main.tf`**

```hcl
resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

- [ ] **Step 4: `outputs.tf`**

```hcl
output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "lock_table" {
  value = aws_dynamodb_table.locks.name
}
```

- [ ] **Step 5: Format + validate (no AWS calls)**

Run: `cd terraform/state-backend && terraform fmt -check && terraform init -backend=false -input=false && terraform validate && cd -`
Expected: `Success! The configuration is valid.`

- [ ] **Step 6: Commit**

```bash
git add terraform/state-backend
git commit -m "feat(tf): add S3+DynamoDB remote state backend bootstrap"
```

---

## Task 3: Terraform network module (VPC, subnets, SGs)

**Files:**
- Create: `terraform/modules/network/variables.tf`
- Create: `terraform/modules/network/main.tf`
- Create: `terraform/modules/network/outputs.tf`

- [ ] **Step 1: `variables.tf`**

```hcl
variable "name" {
  description = "Name prefix for network resources"
  type        = string
  default     = "farfalla"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  description = "Two AZs for RDS subnet group"
  type        = list(string)
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.2.0/24", "10.0.3.0/24"]
}

variable "operator_cidr" {
  description = "CIDR allowed SSH (your IP/32)"
  type        = string
}
```

- [ ] **Step 2: `main.tf`**

```hcl
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.azs[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.name}-public" }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags              = { Name = "${var.name}-private-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ec2" {
  name        = "${var.name}-ec2-sg"
  description = "k3s node: SSH from operator, HTTP/HTTPS public, k8s API from operator"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.operator_cidr]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "k3s API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.operator_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.name}-ec2-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "Postgres 5432 from EC2 SG only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Postgres from k3s node"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.name}-rds-sg" }
}
```

- [ ] **Step 3: `outputs.tf`**

```hcl
output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "ec2_sg_id" {
  value = aws_security_group.ec2.id
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}
```

- [ ] **Step 4: Format check**

Run: `terraform fmt -check terraform/modules/network`
Expected: no output (formatted). Full `validate` runs in Task 7 from the env root.

- [ ] **Step 5: Commit**

```bash
git add terraform/modules/network
git commit -m "feat(tf): add network module (vpc, subnets, security groups)"
```

---

## Task 4: Terraform ECR module

**Files:**
- Create: `terraform/modules/ecr/variables.tf`
- Create: `terraform/modules/ecr/main.tf`
- Create: `terraform/modules/ecr/outputs.tf`

- [ ] **Step 1: `variables.tf`**

```hcl
variable "repositories" {
  description = "ECR repo names to create"
  type        = list(string)
  default     = ["farfalla-backend", "farfalla-frontend"]
}
```

- [ ] **Step 2: `main.tf`**

```hcl
resource "aws_ecr_repository" "this" {
  for_each             = toset(var.repositories)
  name                 = each.value
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
```

- [ ] **Step 3: `outputs.tf`**

```hcl
output "repository_urls" {
  description = "Map of repo name => URL"
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  value = [for v in aws_ecr_repository.this : v.arn]
}
```

- [ ] **Step 4: Format check**

Run: `terraform fmt -check terraform/modules/ecr`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add terraform/modules/ecr
git commit -m "feat(tf): add ECR module with scan-on-push and lifecycle policy"
```

---

## Task 5: Terraform RDS module

**Files:**
- Create: `terraform/modules/rds/variables.tf`
- Create: `terraform/modules/rds/main.tf`
- Create: `terraform/modules/rds/outputs.tf`

- [ ] **Step 1: `variables.tf`**

```hcl
variable "name" {
  type    = string
  default = "farfalla"
}

variable "subnet_ids" {
  description = "Two private subnet IDs"
  type        = list(string)
}

variable "vpc_security_group_ids" {
  type = list(string)
}

variable "db_name" {
  type    = string
  default = "erp"
}

variable "db_username" {
  type    = string
  default = "erp"
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "engine_version" {
  type    = string
  default = "17.2"
}
```

- [ ] **Step 2: `main.tf`**

```hcl
resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.subnet_ids
  tags       = { Name = "${var.name}-db-subnets" }
}

resource "aws_db_instance" "this" {
  identifier             = "${var.name}-pg"
  engine                 = "postgres"
  engine_version         = var.engine_version
  instance_class         = var.instance_class
  allocated_storage      = var.allocated_storage
  storage_type           = "gp3"
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.vpc_security_group_ids
  multi_az               = false
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false
  apply_immediately      = true
}
```

> Note: `random` provider is declared at the env root (Task 7). Module uses it without its own `required_providers` block (inherited).

- [ ] **Step 3: `outputs.tf`**

```hcl
output "endpoint" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "username" {
  value = aws_db_instance.this.username
}

output "password" {
  value     = random_password.db.result
  sensitive = true
}
```

- [ ] **Step 4: Format check**

Run: `terraform fmt -check terraform/modules/rds`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add terraform/modules/rds
git commit -m "feat(tf): add RDS Postgres module (free-tier, private)"
```

---

## Task 6: Terraform EC2/k3s module (+ user_data, instance profile)

**Files:**
- Create: `terraform/modules/ec2-k3s/variables.tf`
- Create: `terraform/modules/ec2-k3s/main.tf`
- Create: `terraform/modules/ec2-k3s/user_data.sh.tftpl`
- Create: `terraform/modules/ec2-k3s/outputs.tf`

- [ ] **Step 1: `variables.tf`**

```hcl
variable "name" {
  type    = string
  default = "farfalla"
}

variable "subnet_id" {
  type = string
}

variable "vpc_security_group_ids" {
  type = list(string)
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "key_name" {
  description = "Existing EC2 key pair name for SSH"
  type        = string
}

variable "k3s_version" {
  type    = string
  default = "v1.31.4+k3s1"
}

variable "root_volume_size" {
  type    = number
  default = 30
}
```

- [ ] **Step 2: `user_data.sh.tftpl`**

```bash
#!/bin/bash
set -euo pipefail

# Install k3s with built-in Traefik, kubeconfig readable, API cert valid for the Elastic IP.
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${k3s_version}" \
  sh -s - server \
    --write-kubeconfig-mode 644 \
    --tls-san ${elastic_ip}

# Wait for node ready
until kubectl get nodes 2>/dev/null | grep -q ' Ready'; do sleep 5; done

# Expose externally-usable kubeconfig (server points to the Elastic IP)
sed "s/127.0.0.1/${elastic_ip}/g" /etc/rancher/k3s/k3s.yaml > /home/ubuntu/kubeconfig.yaml || true
chown ubuntu:ubuntu /home/ubuntu/kubeconfig.yaml || true
```

- [ ] **Step 3: `main.tf`**

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Instance profile so the node can pull from ECR
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-k3s-node"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ecr_ro" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.name}-k3s-node"
  role = aws_iam_role.node.name
}

resource "aws_eip" "node" {
  domain = "vpc"
  tags   = { Name = "${var.name}-k3s-eip" }
}

resource "aws_instance" "node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.vpc_security_group_ids
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.node.name

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    k3s_version = var.k3s_version
    elastic_ip  = aws_eip.node.public_ip
  })

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  tags = { Name = "${var.name}-k3s" }
}

resource "aws_eip_association" "node" {
  instance_id   = aws_instance.node.id
  allocation_id = aws_eip.node.id
}
```

- [ ] **Step 4: `outputs.tf`**

```hcl
output "public_ip" {
  value = aws_eip.node.public_ip
}

output "instance_id" {
  value = aws_instance.node.id
}

output "sslip_domain" {
  description = "Wildcard-friendly host base"
  value       = "${replace(aws_eip.node.public_ip, ".", "-")}.sslip.io"
}
```

- [ ] **Step 5: Format check**

Run: `terraform fmt -check terraform/modules/ec2-k3s`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add terraform/modules/ec2-k3s
git commit -m "feat(tf): add ec2-k3s module with EIP, instance profile, user_data"
```

---

## Task 7: Terraform prod env (wire modules + GitHub OIDC + full validate)

**Files:**
- Create: `terraform/envs/prod/versions.tf`
- Create: `terraform/envs/prod/backend.tf`
- Create: `terraform/envs/prod/variables.tf`
- Create: `terraform/envs/prod/main.tf`
- Create: `terraform/envs/prod/outputs.tf`
- Create: `terraform/envs/prod/terraform.tfvars.example`

- [ ] **Step 1: `versions.tf`**

```hcl
terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region
}
```

- [ ] **Step 2: `backend.tf`**

```hcl
# Values supplied at init: terraform init -backend-config=...
# bucket/dynamodb_table created by terraform/state-backend (Task 2).
terraform {
  backend "s3" {
    key     = "prod/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
```

- [ ] **Step 3: `variables.tf`**

```hcl
variable "region" {
  type    = string
  default = "us-east-1"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "operator_cidr" {
  description = "Your public IP in CIDR form, e.g. 1.2.3.4/32"
  type        = string
}

variable "key_name" {
  description = "Existing EC2 key pair for SSH"
  type        = string
}

variable "github_repo" {
  description = "owner/repo allowed to assume the CD role via OIDC"
  type        = string
}
```

- [ ] **Step 4: `main.tf`**

```hcl
module "network" {
  source        = "../../modules/network"
  azs           = var.azs
  operator_cidr = var.operator_cidr
}

module "ecr" {
  source = "../../modules/ecr"
}

module "rds" {
  source                 = "../../modules/rds"
  subnet_ids             = module.network.private_subnet_ids
  vpc_security_group_ids = [module.network.rds_sg_id]
}

module "ec2_k3s" {
  source                 = "../../modules/ec2-k3s"
  subnet_id              = module.network.public_subnet_id
  vpc_security_group_ids = [module.network.ec2_sg_id]
  key_name               = var.key_name
}

# --- GitHub OIDC role for CD (push to ECR) ---
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "cd_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "cd" {
  name               = "farfalla-github-cd"
  assume_role_policy = data.aws_iam_policy_document.cd_assume.json
}

data "aws_iam_policy_document" "cd_perms" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = module.ecr.repository_arns
  }
}

resource "aws_iam_role_policy" "cd" {
  name   = "farfalla-cd-ecr"
  role   = aws_iam_role.cd.id
  policy = data.aws_iam_policy_document.cd_perms.json
}
```

> Assumes the GitHub OIDC provider already exists in the account (created once, account-wide). Runbook documents creating it if absent.

- [ ] **Step 5: `outputs.tf`**

```hcl
output "node_public_ip" {
  value = module.ec2_k3s.public_ip
}

output "sslip_domain" {
  value = module.ec2_k3s.sslip_domain
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "rds_password" {
  value     = module.rds.password
  sensitive = true
}

output "cd_role_arn" {
  value = aws_iam_role.cd.arn
}
```

- [ ] **Step 6: `terraform.tfvars.example`**

```hcl
region        = "us-east-1"
operator_cidr = "1.2.3.4/32"     # replace with YOUR_IP/32
key_name      = "my-ec2-keypair" # existing key pair name
github_repo   = "lucas-matricarde/Cloud"
```

- [ ] **Step 7: Format + full validate (offline)**

Run:
```bash
cd terraform/envs/prod
terraform fmt -check -recursive ../../
terraform init -backend=false -input=false
terraform validate
cd -
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 8: Commit**

```bash
git add terraform/envs/prod
git commit -m "feat(tf): wire prod env (network, ecr, rds, ec2-k3s, github-oidc)"
```

---

## Task 8: ArgoCD bootstrap (project + app-of-apps)

**Files:**
- Create: `k8s/bootstrap/project.yaml`
- Create: `k8s/bootstrap/app-of-apps.yaml`

> Replace `__GITHUB_REPO_URL__` at deploy time (e.g. `https://github.com/lucas-matricarde/Cloud.git`). Runbook documents this.

- [ ] **Step 1: `project.yaml`**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: farfalla
  namespace: argocd
spec:
  description: Farfalla platform and app
  sourceRepos:
    - "*"
  destinations:
    - namespace: "*"
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: "*"
      kind: "*"
```

- [ ] **Step 2: `app-of-apps.yaml`**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: argocd
spec:
  project: farfalla
  source:
    repoURL: __GITHUB_REPO_URL__
    targetRevision: main
    path: k8s/platform
    directory:
      recurse: true
      include: "{cert-manager/application.yaml,kube-prometheus-stack/application.yaml,loki/application.yaml}"
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: farfalla-app
  namespace: argocd
spec:
  project: farfalla
  source:
    repoURL: __GITHUB_REPO_URL__
    targetRevision: main
    path: k8s/apps/farfalla
  destination:
    server: https://kubernetes.default.svc
    namespace: farfalla
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

- [ ] **Step 3: Validate YAML parses**

Run: `kubeconform -strict -ignore-missing-schemas k8s/bootstrap/project.yaml k8s/bootstrap/app-of-apps.yaml`
Expected: each file reported valid (CRDs skipped as missing-schema).

- [ ] **Step 4: Commit**

```bash
git add k8s/bootstrap
git commit -m "feat(gitops): add ArgoCD project and app-of-apps"
```

---

## Task 9: Platform — cert-manager (Application + ClusterIssuer)

**Files:**
- Create: `k8s/platform/cert-manager/application.yaml`
- Create: `k8s/platform/cert-manager/cluster-issuer.yaml`

- [ ] **Step 1: `application.yaml`** (Helm chart via ArgoCD, CRDs enabled)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
spec:
  project: farfalla
  source:
    repoURL: https://charts.jetstack.io
    chart: cert-manager
    targetRevision: v1.16.2
    helm:
      values: |
        crds:
          enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

- [ ] **Step 2: `cluster-issuer.yaml`** (Let's Encrypt, Traefik HTTP-01)

> Replace `__ACME_EMAIL__` at deploy time.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: __ACME_EMAIL__
    privateKeySecretRef:
      name: letsencrypt-prod-account
    solvers:
      - http01:
          ingress:
            class: traefik
```

> The ClusterIssuer is applied by the farfalla app kustomization (Task 14) so it lands after cert-manager CRDs exist. It lives here for cohesion; Task 14 references it.

- [ ] **Step 3: Validate**

Run: `kubeconform -strict -ignore-missing-schemas k8s/platform/cert-manager/*.yaml`
Expected: valid (CRD/Application schemas skipped).

- [ ] **Step 4: Commit**

```bash
git add k8s/platform/cert-manager
git commit -m "feat(gitops): add cert-manager app and Let's Encrypt ClusterIssuer"
```

---

## Task 10: Platform — kube-prometheus-stack

**Files:**
- Create: `k8s/platform/kube-prometheus-stack/application.yaml`

- [ ] **Step 1: `application.yaml`**

> Replace `__GRAFANA_HOST__` (e.g. `grafana.1-2-3-4.sslip.io`) and `__GRAFANA_ADMIN_PASSWORD__` at deploy time.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prometheus-stack
  namespace: argocd
spec:
  project: farfalla
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 66.2.1
    helm:
      values: |
        grafana:
          adminPassword: __GRAFANA_ADMIN_PASSWORD__
          ingress:
            enabled: true
            ingressClassName: traefik
            hosts:
              - __GRAFANA_HOST__
        prometheus:
          prometheusSpec:
            serviceMonitorSelectorNilUsesHelmValues: false
            retention: 7d
            resources:
              requests:
                memory: 400Mi
        alertmanager:
          enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

> `serviceMonitorSelectorNilUsesHelmValues: false` lets Prometheus pick up the backend ServiceMonitor (Task 12). `ServerSideApply` avoids the large-CRD annotation limit.

- [ ] **Step 2: Validate**

Run: `kubeconform -strict -ignore-missing-schemas k8s/platform/kube-prometheus-stack/application.yaml`
Expected: valid.

- [ ] **Step 3: Commit**

```bash
git add k8s/platform/kube-prometheus-stack
git commit -m "feat(gitops): add kube-prometheus-stack with Grafana ingress"
```

---

## Task 11: Platform — Loki + Promtail

**Files:**
- Create: `k8s/platform/loki/application.yaml`

- [ ] **Step 1: `application.yaml`** (single-binary Loki + Promtail via grafana chart)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: loki-stack
  namespace: argocd
spec:
  project: farfalla
  source:
    repoURL: https://grafana.github.io/helm-charts
    chart: loki-stack
    targetRevision: 2.10.2
    helm:
      values: |
        loki:
          isDefault: false
          persistence:
            enabled: true
            size: 5Gi
        promtail:
          enabled: true
        grafana:
          enabled: false
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

> Grafana from kube-prometheus-stack is reused; this chart's bundled Grafana is disabled. Add Loki as a Grafana datasource via the runbook (or a sidecar datasource ConfigMap — noted as future).

- [ ] **Step 2: Validate**

Run: `kubeconform -strict -ignore-missing-schemas k8s/platform/loki/application.yaml`
Expected: valid.

- [ ] **Step 3: Commit**

```bash
git add k8s/platform/loki
git commit -m "feat(gitops): add Loki + Promtail log stack"
```

---

## Task 12: App manifests — backend (deploy, svc, config, secret example, ServiceMonitor)

**Files:**
- Create: `k8s/apps/farfalla/namespace.yaml`
- Create: `k8s/apps/farfalla/backend-config.yaml`
- Create: `k8s/apps/farfalla/backend-secret.example.yaml`
- Create: `k8s/apps/farfalla/backend-deployment.yaml`
- Create: `k8s/apps/farfalla/backend-service.yaml`
- Create: `k8s/apps/farfalla/backend-servicemonitor.yaml`

- [ ] **Step 1: `namespace.yaml`**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: farfalla
```

- [ ] **Step 2: `backend-config.yaml`** (non-secret env; RDS host filled at deploy)

> Replace `__RDS_ENDPOINT__` at deploy time (Terraform output `rds_endpoint`).

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
  namespace: farfalla
data:
  SPRING_PROFILES_ACTIVE: "prod"
  SPRING_DATASOURCE_URL: "jdbc:postgresql://__RDS_ENDPOINT__:5432/erp"
  SERVER_PORT: "8080"
```

- [ ] **Step 3: `backend-secret.example.yaml`** (template; real secret never committed)

```yaml
# Copy to backend-secret.yaml, fill values, apply manually (gitignored).
apiVersion: v1
kind: Secret
metadata:
  name: backend-secret
  namespace: farfalla
type: Opaque
stringData:
  SPRING_DATASOURCE_USERNAME: "erp"
  SPRING_DATASOURCE_PASSWORD: "REPLACE_WITH_RDS_PASSWORD"
```

- [ ] **Step 4: `backend-deployment.yaml`**

> Replace `__BACKEND_IMAGE__` — managed by Kustomize `images:` (Task 14) and bumped by CD.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: farfalla
  labels:
    app: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
        - name: backend
          image: __BACKEND_IMAGE__
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: backend-config
            - secretRef:
                name: backend-secret
          readinessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 20
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              memory: 768Mi
```

- [ ] **Step 5: `backend-service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: farfalla
  labels:
    app: backend
spec:
  selector:
    app: backend
  ports:
    - name: http
      port: 8080
      targetPort: 8080
```

- [ ] **Step 6: `backend-servicemonitor.yaml`** (Prometheus scrape of actuator)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: backend
  namespace: farfalla
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: backend
  endpoints:
    - port: http
      path: /actuator/prometheus
      interval: 15s
```

- [ ] **Step 7: Validate**

Run: `kubeconform -strict -ignore-missing-schemas k8s/apps/farfalla/namespace.yaml k8s/apps/farfalla/backend-*.yaml`
Expected: valid (ServiceMonitor CRD skipped).

- [ ] **Step 8: Commit**

```bash
git add k8s/apps/farfalla/namespace.yaml k8s/apps/farfalla/backend-*.yaml
git commit -m "feat(gitops): add backend deployment, service, config, ServiceMonitor"
```

---

## Task 13: App manifests — frontend (deploy + svc)

**Files:**
- Create: `k8s/apps/farfalla/frontend-deployment.yaml`
- Create: `k8s/apps/farfalla/frontend-service.yaml`

- [ ] **Step 1: `frontend-deployment.yaml`**

> Replace `__FRONTEND_IMAGE__` — managed by Kustomize (Task 14), bumped by CD. Frontend nginx serves on port 80.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: farfalla
  labels:
    app: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
        - name: frontend
          image: __FRONTEND_IMAGE__
          ports:
            - containerPort: 80
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 10
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              memory: 128Mi
```

- [ ] **Step 2: `frontend-service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: farfalla
  labels:
    app: frontend
spec:
  selector:
    app: frontend
  ports:
    - name: http
      port: 80
      targetPort: 80
```

- [ ] **Step 3: Validate**

Run: `kubeconform -strict -ignore-missing-schemas k8s/apps/farfalla/frontend-*.yaml`
Expected: valid.

- [ ] **Step 4: Commit**

```bash
git add k8s/apps/farfalla/frontend-*.yaml
git commit -m "feat(gitops): add frontend deployment and service"
```

---

## Task 14: App manifests — ingress, TLS cert, ClusterIssuer, kustomization

**Files:**
- Create: `k8s/apps/farfalla/certificate.yaml`
- Create: `k8s/apps/farfalla/ingressroute.yaml`
- Create: `k8s/apps/farfalla/kustomization.yaml`

> Replace `__APP_HOST__` (e.g. `app.1-2-3-4.sslip.io`) at deploy time. Routing: `/` → frontend:80, `/api`, `/actuator`, `/swagger-ui` → backend:8080. TLS via cert-manager.

- [ ] **Step 1: `certificate.yaml`**

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app-tls
  namespace: farfalla
spec:
  secretName: app-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - __APP_HOST__
```

- [ ] **Step 2: `ingressroute.yaml`** (Traefik CRD, built into k3s)

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: farfalla
  namespace: farfalla
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`__APP_HOST__`) && (PathPrefix(`/api`) || PathPrefix(`/actuator`) || PathPrefix(`/swagger-ui`) || PathPrefix(`/v3/api-docs`))
      kind: Rule
      services:
        - name: backend
          port: 8080
    - match: Host(`__APP_HOST__`)
      kind: Rule
      services:
        - name: frontend
          port: 80
  tls:
    secretName: app-tls
```

- [ ] **Step 3: `kustomization.yaml`** (CD bumps `images:` newTag)

> Replace `__ECR_BACKEND_REPO__` / `__ECR_FRONTEND_REPO__` at deploy time (Terraform output `ecr_repository_urls`). `newName` set once; CD updates `newTag`.

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: farfalla
resources:
  - namespace.yaml
  - backend-config.yaml
  - backend-deployment.yaml
  - backend-service.yaml
  - backend-servicemonitor.yaml
  - frontend-deployment.yaml
  - frontend-service.yaml
  - certificate.yaml
  - ingressroute.yaml
  - ../../platform/cert-manager/cluster-issuer.yaml
images:
  - name: __BACKEND_IMAGE__
    newName: __ECR_BACKEND_REPO__
    newTag: latest
  - name: __FRONTEND_IMAGE__
    newName: __ECR_FRONTEND_REPO__
    newTag: latest
```

> `backend-secret` is applied out-of-band (gitignored) and is intentionally NOT in `resources`.

- [ ] **Step 4: Validate kustomize build renders**

Run: `kustomize build k8s/apps/farfalla > /tmp/farfalla-render.yaml && kubeconform -strict -ignore-missing-schemas /tmp/farfalla-render.yaml`
Expected: build succeeds; kubeconform valid (Traefik/cert-manager CRDs skipped).

- [ ] **Step 5: Commit**

```bash
git add k8s/apps/farfalla/certificate.yaml k8s/apps/farfalla/ingressroute.yaml k8s/apps/farfalla/kustomization.yaml
git commit -m "feat(gitops): add Traefik IngressRoute, TLS certificate, kustomization"
```

---

## Task 15: CI workflow (infra validation + app build/test on PR)

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: `ci.yml`**

```yaml
name: CI

on:
  pull_request:
    branches: [main]

jobs:
  infra:
    name: Validate infra
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.9.8"
      - name: terraform fmt
        run: terraform fmt -check -recursive terraform
      - name: terraform validate (prod)
        working-directory: terraform/envs/prod
        run: |
          terraform init -backend=false -input=false
          terraform validate
      - name: Install kubeconform + kustomize
        run: |
          curl -sSL https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz | tar xz -C /usr/local/bin kubeconform
          curl -sSL https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.4.3/kustomize_v5.4.3_linux_amd64.tar.gz | tar xz -C /usr/local/bin kustomize
      - name: Render + validate manifests
        run: |
          kustomize build k8s/apps/farfalla > /tmp/render.yaml
          kubeconform -strict -ignore-missing-schemas /tmp/render.yaml
          kubeconform -strict -ignore-missing-schemas k8s/bootstrap k8s/platform

  app:
    name: Build & test ERP-Farfalla
    runs-on: ubuntu-latest
    steps:
      - name: Checkout app repo
        uses: actions/checkout@v4
        with:
          repository: ${{ vars.APP_REPO }}
          ref: ${{ vars.APP_REF }}
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "21"
          cache: maven
      - name: Backend verify
        working-directory: backend
        run: mvn -B verify
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: npm
          cache-dependency-path: frontend/package-lock.json
      - name: Frontend build
        working-directory: frontend
        run: |
          npm ci
          npm run build
```

> Repo variables `APP_REPO` (e.g. `lucas-matricarde/erp-farfalla`) and `APP_REF` (e.g. `main`) set in GitHub settings. Documented in runbook.

- [ ] **Step 2: Lint the workflow**

Run: `actionlint .github/workflows/ci.yml`
Expected: no errors. (Install: `brew install actionlint` if missing.)

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: validate infra and build/test app on PR"
```

---

## Task 16: CD workflow (build→ECR via OIDC + GitOps tag bump)

**Files:**
- Create: `.github/workflows/cd.yml`

- [ ] **Step 1: `cd.yml`**

```yaml
name: CD

on:
  push:
    branches: [main]

permissions:
  id-token: write   # OIDC
  contents: write   # commit manifest bump

concurrency:
  group: cd-${{ github.ref }}
  cancel-in-progress: false

env:
  AWS_REGION: us-east-1

jobs:
  build-deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout GitOps repo
        uses: actions/checkout@v4

      - name: Checkout app repo
        uses: actions/checkout@v4
        with:
          repository: ${{ vars.APP_REPO }}
          ref: ${{ vars.APP_REF }}
          path: app

      - name: Configure AWS via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.CD_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to ECR
        id: ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build & push backend
        env:
          REGISTRY: ${{ steps.ecr.outputs.registry }}
          TAG: ${{ github.sha }}
        run: |
          docker build --target prod -t "$REGISTRY/farfalla-backend:$TAG" app/backend
          docker push "$REGISTRY/farfalla-backend:$TAG"

      - name: Build & push frontend
        env:
          REGISTRY: ${{ steps.ecr.outputs.registry }}
          TAG: ${{ github.sha }}
        run: |
          docker build -t "$REGISTRY/farfalla-frontend:$TAG" app/frontend
          docker push "$REGISTRY/farfalla-frontend:$TAG"

      - name: Install kustomize
        run: curl -sSL https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.4.3/kustomize_v5.4.3_linux_amd64.tar.gz | tar xz -C /usr/local/bin kustomize

      - name: Bump image tags in GitOps manifest
        working-directory: k8s/apps/farfalla
        env:
          REGISTRY: ${{ steps.ecr.outputs.registry }}
          TAG: ${{ github.sha }}
        run: |
          kustomize edit set image "$REGISTRY/farfalla-backend:$TAG"
          kustomize edit set image "$REGISTRY/farfalla-frontend:$TAG"

      - name: Commit & push manifest bump
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add k8s/apps/farfalla/kustomization.yaml
          git commit -m "chore(deploy): bump images to ${GITHUB_SHA::7}" || echo "no changes"
          git push
```

> Repo variable `CD_ROLE_ARN` = Terraform output `cd_role_arn`. ArgoCD detects the manifest commit and syncs. `kustomize edit set image NAME:TAG` matches the `images[].name` set in Task 14.

- [ ] **Step 2: Lint the workflow**

Run: `actionlint .github/workflows/cd.yml`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/cd.yml
git commit -m "cd: build images to ECR via OIDC and bump GitOps tags on main"
```

---

## Task 17: Operator scripts (cluster bootstrap, ArgoCD install, kubeconfig)

**Files:**
- Create: `scripts/fetch-kubeconfig.sh`
- Create: `scripts/install-argocd.sh`
- Create: `scripts/bootstrap-cluster.sh`

- [ ] **Step 1: `scripts/fetch-kubeconfig.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
# Usage: ./fetch-kubeconfig.sh <EC2_PUBLIC_IP> <SSH_KEY_PATH>
# Pulls the EIP-rewritten kubeconfig the node wrote in user_data.
IP="${1:?EC2 public IP required}"
KEY="${2:?SSH key path required}"

scp -o StrictHostKeyChecking=accept-new -i "$KEY" \
  "ubuntu@${IP}:/home/ubuntu/kubeconfig.yaml" ./kubeconfig
echo "Wrote ./kubeconfig — use: export KUBECONFIG=\$PWD/kubeconfig"
```

- [ ] **Step 2: `scripts/install-argocd.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
# Installs ArgoCD into the cluster. Requires KUBECONFIG pointing at the k3s node.
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.13.2}"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "Waiting for ArgoCD server..."
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

echo "Initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

- [ ] **Step 3: `scripts/bootstrap-cluster.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
# One-time GitOps bootstrap after ArgoCD is installed and manifests are
# placeholder-substituted. Requires KUBECONFIG set.
kubectl apply -f k8s/bootstrap/project.yaml
kubectl apply -f k8s/bootstrap/app-of-apps.yaml
echo "ArgoCD app-of-apps applied. Watch: kubectl -n argocd get applications -w"
```

- [ ] **Step 4: Make executable + shellcheck**

Run:
```bash
chmod +x scripts/*.sh
shellcheck scripts/*.sh
```
Expected: no warnings. (Install: `brew install shellcheck` if missing.)

- [ ] **Step 5: Commit**

```bash
git add scripts
git commit -m "feat(ops): add kubeconfig fetch, ArgoCD install, bootstrap scripts"
```

---

## Task 18: Documentation (architecture + runbook + README finalize)

**Files:**
- Create: `docs/architecture.md`
- Create: `docs/runbook.md`
- Modify: `README.md`

- [ ] **Step 1: `docs/architecture.md`**

```markdown
# Architecture

\`\`\`
Dev push -> GitHub Actions (CI validate / CD build->ECR + tag bump)
                                    |
                       git commit to k8s/ --> ArgoCD (in-cluster) auto-sync
AWS:
  VPC
    public subnet: EC2 t3.small (Elastic IP) -> k3s
       Traefik ingress (built-in) / cert-manager / ArgoCD
       backend + frontend pods / Prometheus, Grafana, Loki
    private subnets (2 AZ): RDS Postgres 17 (db.t3.micro)  SG: 5432 from EC2 SG
  ECR (backend, frontend)  |  S3 + DynamoDB (TF state + lock)
Recruiter -> https://app.<EIP>.sslip.io   https://grafana.<EIP>.sslip.io
\`\`\`

## Components
- **Terraform** (`terraform/`): state-backend (S3+DynamoDB), modules network/ecr/rds/ec2-k3s, prod env + GitHub OIDC role.
- **k3s**: single node, built-in Traefik ingress, cert-manager Let's Encrypt TLS.
- **ArgoCD**: app-of-apps syncs platform (cert-manager, kube-prometheus-stack, loki) and the Farfalla app.
- **GitHub Actions**: CI validates infra + builds/tests app; CD pushes images to ECR (OIDC) and bumps the GitOps tag.
- **Observability**: Prometheus scrapes `/actuator/prometheus` via ServiceMonitor; Grafana dashboards; Loki/Promtail logs.

## Request flow
Recruiter -> app.<EIP>.sslip.io -> Traefik (TLS) -> frontend pod (nginx/Angular); `/api`,`/actuator`,`/swagger-ui` -> backend pod -> RDS over private subnet.

## Security
GitHub OIDC (no static keys), EC2 instance role (ECR pull), RDS private + SG-locked, SSH locked to operator IP.
```

- [ ] **Step 2: `docs/runbook.md`** (deploy order + placeholder substitutions)

```markdown
# Runbook — Deploy from zero

Prereqs: AWS account + creds, an existing EC2 key pair, Terraform, kubectl, kustomize, AWS CLI.

## 1. Remote state
\`\`\`bash
cd terraform/state-backend
terraform init
terraform apply -var state_bucket_name=<globally-unique-bucket>
\`\`\`

## 2. GitHub OIDC provider (once per account, if absent)
\`\`\`bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
\`\`\`

## 3. Provision infra
\`\`\`bash
cd terraform/envs/prod
cp terraform.tfvars.example terraform.tfvars   # edit operator_cidr, key_name, github_repo
terraform init -backend-config="bucket=<bucket>" -backend-config="dynamodb_table=farfalla-tf-locks"
terraform apply
\`\`\`
Note outputs: `node_public_ip`, `sslip_domain`, `ecr_repository_urls`, `rds_endpoint`, `cd_role_arn`, `terraform output -raw rds_password`.

## 4. Substitute placeholders in manifests
Replace before bootstrap (EIP-derived host = dashes, e.g. `1-2-3-4.sslip.io`):
- `__GITHUB_REPO_URL__` (k8s/bootstrap/app-of-apps.yaml)
- `__ACME_EMAIL__` (cert-manager/cluster-issuer.yaml)
- `__GRAFANA_HOST__`, `__GRAFANA_ADMIN_PASSWORD__` (kube-prometheus-stack)
- `__APP_HOST__` (apps/farfalla certificate.yaml, ingressroute.yaml)
- `__RDS_ENDPOINT__` (backend-config.yaml)
- `__ECR_BACKEND_REPO__`, `__ECR_FRONTEND_REPO__` and `__BACKEND_IMAGE__`/`__FRONTEND_IMAGE__` (kustomization.yaml)
Commit and push these to `main`.

## 5. GitHub repo variables
Set: `APP_REPO`, `APP_REF`, `CD_ROLE_ARN`.

## 6. Cluster bootstrap
\`\`\`bash
./scripts/fetch-kubeconfig.sh <node_public_ip> <key.pem>
export KUBECONFIG=$PWD/kubeconfig
./scripts/install-argocd.sh
# create the DB secret out-of-band (gitignored):
kubectl -n farfalla create secret generic backend-secret \
  --from-literal=SPRING_DATASOURCE_USERNAME=erp \
  --from-literal=SPRING_DATASOURCE_PASSWORD="$(cd terraform/envs/prod && terraform output -raw rds_password)"
./scripts/bootstrap-cluster.sh
\`\`\`

## 7. Verify
- `kubectl -n argocd get applications` -> all Synced/Healthy
- `https://app.<EIP>.sslip.io` loads with valid TLS, login works
- `https://grafana.<EIP>.sslip.io` shows JVM/HTTP dashboards
- Push to app repo main -> CD bumps tag -> ArgoCD redeploys

## Teardown
`kubectl delete -f k8s/bootstrap/app-of-apps.yaml` then `terraform destroy` (prod, then state-backend).
```

- [ ] **Step 3: Append deploy pointer to `README.md`** (already references docs — confirm wording)

Ensure README's "Deploy quickstart" line reads:
```markdown
## Deploy quickstart
Full deploy order in `docs/runbook.md`. Architecture in `docs/architecture.md`.
```

- [ ] **Step 4: Sanity-check docs render (no broken fences)**

Run: `grep -c '\`\`\`' docs/architecture.md docs/runbook.md`
Expected: an even count per file (balanced fences).

- [ ] **Step 5: Commit**

```bash
git add docs/architecture.md docs/runbook.md README.md
git commit -m "docs: add architecture diagram and deploy runbook"
```

---

## Final Review (after all tasks)

- [ ] Dispatch a final code reviewer over the whole branch (all 18 commits): correctness of Terraform wiring (module inputs/outputs match), manifest/Kustomize image-name consistency (`images[].name` == deployment image placeholders), workflow OIDC permissions, placeholder inventory matches runbook §4.
- [ ] Confirm no real secrets committed (`git log -p | grep -i password` shows only placeholders/`random_password`).
- [ ] Use superpowers:finishing-a-development-branch to wrap up.

## Notes for the executor
- **No `terraform apply`, no `kubectl apply` against real clusters, no `docker push`.** Validation is offline only (`fmt`, `validate -backend=false`, `kubeconform`, `kustomize build`, `actionlint`, `shellcheck`).
- If a validation tool is missing, install via `brew install <tool>` (terraform, kustomize, kubeconform, actionlint, shellcheck) then re-run.
- Placeholders (`__NAME__`) are intentional and substituted at deploy time per the runbook — they are NOT plan placeholders.
- Type consistency anchors: Kustomize `images[].name` (`__BACKEND_IMAGE__`/`__FRONTEND_IMAGE__`) must equal the `image:` values in `backend-deployment.yaml`/`frontend-deployment.yaml`. ServiceMonitor label `release: kube-prometheus-stack` must match the prometheus release name. RDS `db_name=erp` matches `SPRING_DATASOURCE_URL` path `/erp`.
```
