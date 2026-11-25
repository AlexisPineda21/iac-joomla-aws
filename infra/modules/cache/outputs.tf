output "primary_endpoint" {
  description = "Nombre DNS del nodo primario de Valkey"
  value       = aws_elasticache_replication_group.valkey.primary_endpoint_address
}

output "port" {
  value = aws_elasticache_replication_group.valkey.port
}

output "member_cluster_id" {
  description = "Nodo de Valkey (dimension CacheClusterId en CloudWatch)"
  value       = one(aws_elasticache_replication_group.valkey.member_clusters)
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.slow_log.name
}
