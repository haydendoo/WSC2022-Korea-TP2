# Baseline bastion EC2 instance.
#
# Per the spec: "Unicorn company has strict security policy that doesn't
# allow SSH access from internet, please use suitable AWS service to
# access EC2 instances" and "the existing EC2 instance acts as the
# bastion... make sure that judges can login into this instance". This
# instance is reachable ONLY via AWS Systems Manager Session Manager
# (no key pair, no SSH security group rule, no public SSH path at all).
#
# Connect with:
#   aws ssm start-session --target <instance-id>

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  bastion_user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    dnf update -y

    # AWS CLI v2 ships preinstalled on Amazon Linux 2023; SSM Agent is
    # preinstalled and enabled as well. Everything below is added for
    # day-to-day administration of the EKS/RDS/Redis/EFS solution the
    # participant builds.
    dnf install -y git jq unzip tar gzip htop tree bind-utils mysql

    # Docker (useful for building/testing container images locally before
    # pushing to ECR).
    dnf install -y docker
    systemctl enable --now docker
    usermod -aG docker ec2-user

    # kubectl - matches the current EKS-supported stable release line.
    curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x /usr/local/bin/kubectl

    # eksctl
    curl -fsSL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" \
      | tar xz -C /usr/local/bin eksctl

    # Helm
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    # /usr/local/bin is already on the default PATH for all users, so the
    # tools above are immediately usable - see the spec's note that any
    # installed tools must have their path added to PATH.
    echo 'export PATH=$PATH:/usr/local/bin' >> /etc/profile.d/unicorn-gameday-path.sh
  EOF
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.bastion_instance_type
  subnet_id              = local.bastion_subnet_id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.team_role.name

  # No SSH key pair is configured on purpose - SSM Session Manager is the
  # only supported access path, matching the spec's "no SSH from internet"
  # policy. Do not add key_name here.

  associate_public_ip_address = true

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = var.bastion_root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = local.bastion_user_data

  tags = {
    Name = "${var.name_prefix}-bastion"
    Role = "bastion"
  }
}
