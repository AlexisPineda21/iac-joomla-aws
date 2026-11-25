output "alb_dns_name" {
  value = aws_lb.joomla.dns_name
}

output "alb_arn_suffix" {
  description = "Dimension LoadBalancer de las metricas del ALB"
  value       = aws_lb.joomla.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Dimension TargetGroup de las metricas del ALB"
  value       = aws_lb_target_group.joomla.arn_suffix
}

output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "service_name" {
  value = aws_ecs_service.joomla.name
}

output "service_arn" {
  value = aws_ecs_service.joomla.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.joomla.name
}

output "admin_password_parameter" {
  value = aws_ssm_parameter.admin_password.name
}
