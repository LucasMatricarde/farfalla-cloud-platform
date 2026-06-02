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
