# IAM baseline: recreates what the spec says the security team already
# provided before the competition started.
#
#   - 4 customer-managed policies (UnicornPolicy, AutoScalerPolicy,
#     ELBControllerPolicy, EFSPolicy) - the spec explicitly names these
#     but says "they don't leave any document on this process, you need
#     to figure out how to do it". Consistent with that, this module
#     creates the policies and outputs their ARNs but does NOT attach
#     them anywhere - deciding which roles (cluster role, node role, or
#     IRSA roles you create for the AWS Load Balancer Controller /
#     cluster autoscaler / EFS CSI driver / the app itself) get which
#     policy is participant work.
#   - EKSClusterRole / EKSNodeRole - baseline roles the spec says are
#     "already available to participants" to run a functional EKS
#     cluster. Only the AWS-managed policies EKS itself requires are
#     attached; nothing about the application's own permissions is
#     pre-wired in.
#   - TeamRoleInstanceProfile - the instance profile "ready for you to
#     use" on the bastion, per the spec's Caution note.

# ---------------------------------------------------------------------------
# 1. Security-team-provided policies (UnicornPolicy, AutoScalerPolicy,
#    ELBControllerPolicy, EFSPolicy)
# ---------------------------------------------------------------------------

# UnicornPolicy - "Allow Unicorn Service to run in EKS"
#
# Scoped to what the application itself needs per the Service Details
# section: read its config from AppConfig, read/write refund records to
# its S3 bucket, and read its rotated DB secret. Resource ARNs are scoped
# by var.unicorn_resource_name_pattern rather than left as "*".
data "aws_iam_policy_document" "unicorn" {
  statement {
    sid    = "AppConfigRead"
    effect = "Allow"
    actions = [
      "appconfig:GetLatestConfiguration",
      "appconfig:StartConfigurationSession",
      "appconfig:GetConfiguration",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:appconfig:${var.aws_region}:${data.aws_caller_identity.current.account_id}:application/*",
    ]
  }

  statement {
    sid    = "RefundBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${var.unicorn_resource_name_pattern}/*",
    ]
  }

  statement {
    sid       = "RefundBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${var.unicorn_resource_name_pattern}"]
  }

  statement {
    sid    = "DBSecretRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.unicorn_resource_name_pattern}",
    ]
  }
}

resource "aws_iam_policy" "unicorn" {
  name        = "UnicornPolicy"
  description = "Allow Unicorn Service to run in EKS (AppConfig, refund S3 bucket, DB secret)"
  policy      = data.aws_iam_policy_document.unicorn.json
}

# AutoScalerPolicy - "Allow EKS automatically adjusts the number of nodes
# in your cluster"
#
# This is the standard Kubernetes Cluster Autoscaler IAM policy for AWS
# (see https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler/cloudprovider/aws),
# intended for attachment to whatever role backs the cluster-autoscaler
# service account.
data "aws_iam_policy_document" "autoscaler" {
  statement {
    sid    = "AutoscalerDescribe"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AutoscalerMutate"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeImages",
      "eks:DescribeNodegroup",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "autoscaler" {
  name        = "AutoScalerPolicy"
  description = "Allow EKS automatically adjusts the number of nodes in your cluster (Cluster Autoscaler)"
  policy      = data.aws_iam_policy_document.autoscaler.json
}

# ELBControllerPolicy - "Required by AWS Load Balancer Controller if you
# want to use it"
#
# This is the AWS-published IAM policy for the AWS Load Balancer
# Controller. Upstream source of truth (check for updates before relying
# on this at competition time):
# https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/#option-b-attach-iam-policies-to-nodes
resource "aws_iam_policy" "elb_controller" {
  name        = "ELBControllerPolicy"
  description = "Required by AWS Load Balancer Controller if you want to use it"
  policy      = file("${path.module}/policies/elb-controller-policy.json")
}

# EFSPolicy - "Allow Unicorn Service to connect EFS"
#
# This is the AWS-published IAM policy for the Amazon EFS CSI driver.
data "aws_iam_policy_document" "efs" {
  statement {
    sid    = "EfsDescribe"
    effect = "Allow"
    actions = [
      "elasticfilesystem:DescribeAccessPoints",
      "elasticfilesystem:DescribeFileSystems",
      "elasticfilesystem:DescribeMountTargets",
      "ec2:DescribeAvailabilityZones",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "EfsCreateAccessPoint"
    effect    = "Allow"
    actions   = ["elasticfilesystem:CreateAccessPoint"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/efs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }

  statement {
    sid       = "EfsDeleteAccessPoint"
    effect    = "Allow"
    actions   = ["elasticfilesystem:DeleteAccessPoint"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/efs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }

  statement {
    sid       = "EfsClientMount"
    effect    = "Allow"
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "efs" {
  name        = "EFSPolicy"
  description = "Allow Unicorn Service to connect EFS"
  policy      = data.aws_iam_policy_document.efs.json
}

# ---------------------------------------------------------------------------
# 2. EKSClusterRole / EKSNodeRole - baseline roles "already available to
#    participants" to run a functional EKS cluster.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "eks_cluster_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "EKSClusterRole"
  description        = "Baseline role for creating/running the EKS cluster control plane (participant creates the cluster itself)"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_trust.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

data "aws_iam_policy_document" "eks_node_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "EKSNodeRole"
  description        = "Baseline role for EKS worker nodes / managed node groups (participant creates the node group itself)"
  assume_role_policy = data.aws_iam_policy_document.eks_node_trust.json
}

# Minimum AWS-required policies for any EKS worker node - not an
# architecture decision, EKS will not function without these.
resource "aws_iam_role_policy_attachment" "eks_node_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ---------------------------------------------------------------------------
# 3. TeamRoleInstanceProfile - attached to the bastion (see bastion.tf).
#
# Permissions are intentionally NOT AdministratorAccess. They are a
# documented, configurable set (below) sized to let a competitor drive the
# whole Day 2 build from the bastion: EC2/VPC, EKS, RDS, ElastiCache, EFS,
# S3, AppConfig, ECR, Secrets Manager, CloudWatch/logs, and enough IAM to
# create the roles/policies their solution needs. Tune the exact action
# list below, or layer on more via var.team_role_extra_managed_policy_arns.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "team_role_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "team_role" {
  name               = "TeamRole"
  description        = "Bastion administration role - build/test permissions for the Day 2 practice environment, not AdministratorAccess"
  assume_role_policy = data.aws_iam_policy_document.team_role_trust.json
}

data "aws_iam_policy_document" "team_role_baseline" {
  statement {
    sid    = "ComputeAndNetworking"
    effect = "Allow"
    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "autoscaling:*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ContainersAndOrchestration"
    effect = "Allow"
    actions = [
      "eks:*",
      "ecr:*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DataAndStorage"
    effect = "Allow"
    actions = [
      "rds:*",
      "elasticache:*",
      "elasticfilesystem:*",
      "s3:*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ConfigurationAndSecrets"
    effect = "Allow"
    actions = [
      "appconfig:*",
      "secretsmanager:*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ObservabilityAndVersioning"
    effect = "Allow"
    actions = [
      "cloudwatch:*",
      "logs:*",
    ]
    resources = ["*"]
  }

  # Scoped IAM: participants need to create and wire up roles/policies for
  # EKS add-ons and IRSA (this is the "figure out how to create necessary
  # IAM roles" task from the spec). Deliberately excludes iam:CreateUser,
  # iam:CreateAccessKey, and anything on this TeamRole/TeamRoleInstanceProfile
  # itself - see the NotResource block below.
  statement {
    sid    = "ScopedIamForSolutionRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRoles",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicies",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:ListInstanceProfiles",
      "iam:ListInstanceProfilesForRole",
      "iam:PassRole",
      "iam:CreateOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviders",
    ]
    not_resources = [
      aws_iam_role.team_role.arn,
      aws_iam_instance_profile.team_role.arn,
    ]
  }
}

resource "aws_iam_policy" "team_role_baseline" {
  name        = "TeamRoleBaselinePolicy"
  description = "Documented, non-admin permission set for the bastion/TeamRole - see terraform/iam.tf for the full statement list"
  policy      = data.aws_iam_policy_document.team_role_baseline.json
}

resource "aws_iam_role_policy_attachment" "team_role_baseline" {
  role       = aws_iam_role.team_role.name
  policy_arn = aws_iam_policy.team_role_baseline.arn
}

# Required for SSM Session Manager access to the bastion (no SSH).
resource "aws_iam_role_policy_attachment" "team_role_ssm" {
  role       = aws_iam_role.team_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "team_role_extra" {
  for_each = toset(var.team_role_extra_managed_policy_arns)

  role       = aws_iam_role.team_role.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "team_role" {
  name = "TeamRoleInstanceProfile"
  role = aws_iam_role.team_role.name
}
