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
