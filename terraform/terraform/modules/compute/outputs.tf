output "load_balancer_dns" {
  value = aws_lb.main.dns_name
}

output "target_group_arn" {
  value = aws_lb_target_group.backend.arn
}

output "asg_name" {
  value = aws_autoscaling_group.backend.name
}

output "iam_role_arn" {
  value = aws_iam_role.ec2_role.arn
}
