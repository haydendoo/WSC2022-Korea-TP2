# Baseline environment generator for WSC2022 TP53 Day 2 (Cloud Computing).
#
# This module answers "what did the participant receive when the
# competition started?" - it provisions ONLY the pre-existing baseline:
# IAM policies/roles the security team already created, and the bastion
# EC2 instance. It intentionally does NOT provision EKS, RDS, ElastiCache,
# EFS, the application S3 bucket, AppConfig, ALB, or any Kubernetes
# resources - those are the participant's Day 2 solution.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
