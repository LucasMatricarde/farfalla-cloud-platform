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
