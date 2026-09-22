terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat

  filter {
    name   = "name"
    values = ["RHEL-9.*_HVM-*-x86_64-*-Hourly2-GP3"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── SSH key pair (generated, never leaves the machine) ─────────

resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "demo" {
  key_name_prefix = "ao-demo-"
  public_key      = tls_private_key.ssh.public_key_openssh
}

resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.ssh.private_key_openssh
  filename        = "${path.module}/demo-key.pem"
  file_permission = "0600"
}

# ── VPC + networking ───────────────────────────────────────────

resource "aws_vpc" "demo" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "ao-demo" }
}

resource "aws_internet_gateway" "demo" {
  vpc_id = aws_vpc.demo.id
  tags   = { Name = "ao-demo" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags                    = { Name = "ao-demo-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo.id
  }

  tags = { Name = "ao-demo-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ── Security group ─────────────────────────────────────────────

resource "aws_security_group" "demo" {
  name_prefix = "ao-demo-"
  description = "AO demo host — SSH + HTTP"
  vpc_id      = aws_vpc.demo.id

  dynamic "ingress" {
    for_each = {
      ssh         = { port = 22,   desc = "SSH" }
      http        = { port = 80,   desc = "HTTP" }
      https       = { port = 443,  desc = "nginx TLS (PEM cert)" }
      api_server  = { port = 8443, desc = "Tomcat TLS (Java keystore)" }
      vault       = { port = 8200, desc = "HashiCorp Vault" }
      splunk_ui   = { port = 8000, desc = "Splunk Web UI" }
      splunk_hec  = { port = 8088, desc = "Splunk HTTP Event Collector" }
      splunk_mgmt = { port = 8089, desc = "Splunk Management API" }
    }
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = [var.allowed_cidr]
      description = ingress.value.desc
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "ao-demo" }
}

# ── EC2 instance ───────────────────────────────────────────────

resource "aws_instance" "demo" {
  ami                         = data.aws_ami.rhel9.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.demo.key_name
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.demo.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "ao-demo" }
}

# ── Elastic IP (survives stop / start) ────────────────────────

resource "aws_eip" "demo" {
  instance = aws_instance.demo.id
  domain   = "vpc"
  tags     = { Name = "ao-demo" }
}

# ── Generated Ansible inventory ───────────────────────────────

resource "local_file" "ansible_inventory" {
  content = <<-YAML
    all:
      hosts:
        demo:
          ansible_host: ${aws_eip.demo.public_ip}
          ansible_user: ec2-user
          ansible_ssh_private_key_file: ${abspath(local_sensitive_file.ssh_private_key.filename)}
          ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
  YAML

  filename        = "${path.module}/../playbooks/inventory/hosts.yml"
  file_permission = "0644"
}

resource "terraform_data" "update_env" {
  triggers_replace = aws_eip.demo.public_ip

  provisioner "local-exec" {
    command = <<-SH
      ENV_FILE="${path.module}/../../.env"
      if [ -f "$ENV_FILE" ]; then
        sed -i.bak 's/^DEMO_HOST_IP=.*/DEMO_HOST_IP=${aws_eip.demo.public_ip}/' "$ENV_FILE"
        rm -f "$ENV_FILE.bak"
      fi
    SH
  }
}
