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
