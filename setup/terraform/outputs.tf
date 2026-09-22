output "instance_public_ip" {
  description = "Elastic IP of the demo EC2 instance (stable across stop/start)"
  value       = aws_eip.demo.public_ip
}

output "ssh_command" {
  description = "SSH into the instance"
  value       = "ssh -i ${abspath(local_sensitive_file.ssh_private_key.filename)} ec2-user@${aws_eip.demo.public_ip}"
}

output "cert_nginx_url" {
  description = "nginx TLS endpoint (PEM cert)"
  value       = "https://${aws_eip.demo.public_ip}:443"
}

output "cert_api_url" {
  description = "Tomcat TLS endpoint (Java keystore cert)"
  value       = "https://${aws_eip.demo.public_ip}:8443"
}

output "vault_url" {
  description = "HashiCorp Vault UI and API"
  value       = "http://${aws_eip.demo.public_ip}:8200"
}

output "splunk_url" {
  description = "Splunk Web UI"
  value       = "http://${aws_eip.demo.public_ip}:8000"
}
