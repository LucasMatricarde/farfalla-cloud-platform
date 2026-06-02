output "repository_urls" {
  description = "Map of repo name => URL"
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  value = [for v in aws_ecr_repository.this : v.arn]
}
