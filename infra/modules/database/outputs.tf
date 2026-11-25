output "address" {
  description = "Nombre DNS de la instancia RDS"
  value       = aws_db_instance.mysql.address
}

output "port" {
  value = aws_db_instance.mysql.port
}

output "endpoint" {
  description = "Direccion:puerto de la instancia RDS"
  value       = aws_db_instance.mysql.endpoint
}

output "instance_id" {
  description = "Identificador de la instancia (dimension DBInstanceIdentifier en CloudWatch)"
  value       = aws_db_instance.mysql.identifier
}

output "log_group_names" {
  description = "Grupos de logs de RDS en CloudWatch (error y slowquery)"
  value       = [for g in aws_cloudwatch_log_group.rds : g.name]
}
