output "joomla_url" {
  description = "URL publica del sitio Joomla (a traves del balanceador)"
  value       = "http://${module.compute.alb_dns_name}"
}

output "joomla_admin_url" {
  description = "Panel de administracion de Joomla (usuario: admin_username)"
  value       = "http://${module.compute.alb_dns_name}/administrator"
}

output "health_url" {
  description = "Endpoint de salud (MySQL, Valkey y commit desplegado)"
  value       = "http://${module.compute.alb_dns_name}/health.php"
}

output "admin_password_command" {
  description = "Comando para ver la contrasena del superusuario de Joomla"
  value       = "aws ssm get-parameter --name ${module.compute.admin_password_parameter} --with-decryption --query Parameter.Value --output text --region ${var.aws_region}"
}

output "dashboard_url" {
  description = "Dashboard de CloudWatch"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${module.monitoring.dashboard_name}"
}

output "alarm_names" {
  description = "Alarmas de CloudWatch creadas"
  value       = module.monitoring.alarm_names
}

output "rds_endpoint" {
  description = "Endpoint de la base de datos relacional (RDS for MySQL)"
  value       = module.database.endpoint
}

output "valkey_endpoint" {
  description = "Endpoint de la base de datos en memoria (ElastiCache for Valkey)"
  value       = "${module.cache.primary_endpoint}:${module.cache.port}"
}

output "ecs_cluster_name" {
  description = "Cluster de ECS"
  value       = module.compute.cluster_name
}

output "ecs_service_name" {
  description = "Servicio de ECS"
  value       = module.compute.service_name
}

output "logs_command" {
  description = "Comando para ver los logs del contenedor en tiempo real"
  value       = "aws logs tail ${module.compute.log_group_name} --follow --region ${var.aws_region}"
}
