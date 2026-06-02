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
