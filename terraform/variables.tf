variable "aws_region" {
  description = "AWS region to deploy the baseline environment into."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix applied to the names of all resources created by this baseline module."
  type        = string
  default     = "unicorn-gameday"
}

variable "tags" {
  description = "Additional tags merged into every resource created by this module."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Networking (bastion-only baseline, see baseline.tf)
# ---------------------------------------------------------------------------

variable "create_baseline_network" {
  description = <<-EOT
    Whether to create a minimal VPC/subnet/internet gateway to host the
    bastion instance. This is ONLY enough networking to make the bastion
    reachable via SSM - it is not, and must not be mistaken for, the
    highly-available VPC architecture participants are expected to design
    for their EKS solution (Phase I of the re-platform schedule).

    Set to false if you'd rather point the bastion at your account's
    existing default VPC via var.vpc_id / var.subnet_id.
  EOT
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "CIDR block for the baseline VPC (only used when create_baseline_network = true)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the bastion's public subnet (only used when create_baseline_network = true)."
  type        = string
  default     = "10.0.0.0/24"
}

variable "vpc_id" {
  description = "Existing VPC ID to launch the bastion into. Only used when create_baseline_network = false; defaults to the account's default VPC if left null."
  type        = string
  default     = null
}

variable "subnet_id" {
  description = "Existing subnet ID to launch the bastion into. Only used when create_baseline_network = false; defaults to a default subnet in the default VPC if left null."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Bastion EC2
# ---------------------------------------------------------------------------

variable "bastion_instance_type" {
  description = "Instance type for the bastion/administration host."
  type        = string
  default     = "t3.medium"
}

variable "bastion_root_volume_size" {
  description = "Root EBS volume size (GiB) for the bastion instance."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# IAM (see iam.tf)
# ---------------------------------------------------------------------------

variable "unicorn_resource_name_pattern" {
  description = <<-EOT
    Naming pattern (with a trailing "*") used to scope UnicornPolicy's
    access to the S3 bucket and Secrets Manager secret the application
    will use, without granting access to every bucket/secret in the
    account. Participants name their actual bucket/secret to match this
    pattern (default matches the "unicorn-*" style names used in the
    spec's example configs, e.g. "unicorn-us-es-ws-1903").
  EOT
  type        = string
  default     = "unicorn-*"
}

variable "team_role_extra_managed_policy_arns" {
  description = <<-EOT
    Additional AWS-managed or customer-managed policy ARNs to attach to
    TeamRole (the role behind TeamRoleInstanceProfile), on top of the
    baseline SSM + team_role_baseline policies this module always attaches.

    Use this to tune the bastion's permissions for your practice run
    without editing iam.tf - the goal is a documented, adjustable
    permission set rather than AdministratorAccess.
  EOT
  type        = list(string)
  default     = []
}
