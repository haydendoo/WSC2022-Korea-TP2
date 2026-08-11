output "bastion_instance_id" {
  description = "Instance ID of the bastion host. Connect with: aws ssm start-session --target <this-id>"
  value       = aws_instance.bastion.id
}

output "bastion_connect_command" {
  description = "Ready-to-run command to open an SSM session on the bastion."
  value       = "aws ssm start-session --target ${aws_instance.bastion.id} --region ${var.aws_region}"
}

output "bastion_vpc_id" {
  description = "VPC ID the bastion was launched into."
  value       = local.bastion_vpc_id
}

output "bastion_subnet_id" {
  description = "Subnet ID the bastion was launched into."
  value       = local.bastion_subnet_id
}

output "eks_cluster_role_arn" {
  description = "ARN of the baseline EKSClusterRole."
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  description = "ARN of the baseline EKSNodeRole."
  value       = aws_iam_role.eks_node.arn
}

output "team_role_arn" {
  description = "ARN of the role behind TeamRoleInstanceProfile."
  value       = aws_iam_role.team_role.arn
}

output "team_role_instance_profile_name" {
  description = "Name of the instance profile attached to the bastion (TeamRoleInstanceProfile)."
  value       = aws_iam_instance_profile.team_role.name
}

output "security_team_policy_arns" {
  description = "ARNs of the 4 policies the security team provided (UnicornPolicy, AutoScalerPolicy, ELBControllerPolicy, EFSPolicy). Deciding which roles to attach these to is participant work."
  value = {
    UnicornPolicy       = aws_iam_policy.unicorn.arn
    AutoScalerPolicy    = aws_iam_policy.autoscaler.arn
    ELBControllerPolicy = aws_iam_policy.elb_controller.arn
    EFSPolicy           = aws_iam_policy.efs.arn
  }
}
