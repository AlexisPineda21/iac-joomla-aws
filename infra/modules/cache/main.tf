# ---------------------------------------------------------------------------
# Base de datos en memoria gestionada: Amazon ElastiCache for Valkey
# Valkey es el fork de codigo abierto de Redis (Linux Foundation). Joomla lo usa con su
# manejador "Redis" para guardar la cache de paginas/modulos (DB 0) y las sesiones (DB 1).
# ---------------------------------------------------------------------------

# Slow log de Valkey (comandos lentos) en CloudWatch Logs
resource "aws_cloudwatch_log_group" "slow_log" {
  name              = "/aws/elasticache/${var.project_name}-valkey/slow-log"
  retention_in_days = var.log_retention_days
}

resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.project_name}-cache-subnets"
  description = "Subredes privadas para ElastiCache"
  subnet_ids  = var.private_subnet_ids

  tags = { Name = "${var.project_name}-cache-subnets" }
}

resource "aws_elasticache_replication_group" "valkey" {
  replication_group_id = "${var.project_name}-valkey"
  description          = "Valkey para cache y sesiones de Joomla"

  engine               = "valkey"
  engine_version       = var.engine_version
  parameter_group_name = "default.valkey${split(".", var.engine_version)[0]}" # p. ej. default.valkey8
  node_type            = var.node_type
  num_cache_clusters   = 1 # Un solo nodo (sin replicas) para el laboratorio
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [var.security_group_id]

  automatic_failover_enabled = false
  multi_az_enabled           = false

  # Cifrado en reposo activado. Sin TLS en transito: el trafico no sale de la VPC
  # y el grupo de seguridad solo permite al contenedor de Joomla.
  at_rest_encryption_enabled = true
  transit_encryption_enabled = false

  snapshot_retention_limit = 0
  apply_immediately        = true

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.slow_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  tags = { Name = "${var.project_name}-valkey" }
}
