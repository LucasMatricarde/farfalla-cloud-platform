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
