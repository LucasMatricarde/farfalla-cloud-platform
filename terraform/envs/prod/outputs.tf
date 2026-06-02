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
