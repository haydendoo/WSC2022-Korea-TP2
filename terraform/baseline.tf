# Minimal, OPTIONAL networking to make the bastion instance reachable.
#
# This is deliberately tiny: one VPC, one public subnet, one internet
# gateway. It exists only so the bastion can reach AWS SSM endpoints and
# so the AMI lookup/instance boot works in an account with no default VPC.
#
# It is NOT the participant's EKS network architecture. Phase I of the
# spec ("Build a high availability, resilient basic infrastructure
# environment for Unicorn Service... VPC, Security Group etc.") is
# explicitly participant work - do not extend this file to build that for
# them (multiple AZs, private subnets, NAT, etc.).

data "aws_vpc" "default" {
  count   = var.create_baseline_network ? 0 : (var.vpc_id == null ? 1 : 0)
  default = true
}

data "aws_subnets" "default" {
  count = var.create_baseline_network ? 0 : (var.subnet_id == null ? 1 : 0)

  filter {
    name   = "vpc-id"
    values = [var.vpc_id != null ? var.vpc_id : data.aws_vpc.default[0].id]
  }
}

resource "aws_vpc" "bastion" {
  count = var.create_baseline_network ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "bastion" {
  count = var.create_baseline_network ? 1 : 0

  vpc_id = aws_vpc.bastion[0].id
  tags   = { Name = "${var.name_prefix}-igw" }
}

resource "aws_subnet" "bastion_public" {
  count = var.create_baseline_network ? 1 : 0

  vpc_id                  = aws_vpc.bastion[0].id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true

  tags = { Name = "${var.name_prefix}-bastion-public" }
}

resource "aws_route_table" "bastion_public" {
  count = var.create_baseline_network ? 1 : 0

  vpc_id = aws_vpc.bastion[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.bastion[0].id
  }

  tags = { Name = "${var.name_prefix}-bastion-public-rt" }
}

resource "aws_route_table_association" "bastion_public" {
  count = var.create_baseline_network ? 1 : 0

  subnet_id      = aws_subnet.bastion_public[0].id
  route_table_id = aws_route_table.bastion_public[0].id
}

locals {
  bastion_vpc_id = var.create_baseline_network ? aws_vpc.bastion[0].id : (
    var.vpc_id != null ? var.vpc_id : data.aws_vpc.default[0].id
  )
  bastion_subnet_id = var.create_baseline_network ? aws_subnet.bastion_public[0].id : (
    var.subnet_id != null ? var.subnet_id : data.aws_subnets.default[0].ids[0]
  )
}

# No inbound rules: management is via AWS Systems Manager Session Manager
# only, per the spec's "strict security policy that doesn't allow SSH
# access from internet". All outbound is allowed so the SSM agent, yum,
# and AWS CLI can reach AWS/package endpoints.
resource "aws_security_group" "bastion" {
  name_prefix = "${var.name_prefix}-bastion-"
  description = "Bastion host - no inbound access, SSM Session Manager only"
  vpc_id      = local.bastion_vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-bastion-sg" }

  lifecycle {
    create_before_destroy = true
  }
}
