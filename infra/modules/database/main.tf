# ---------------------------------------------------------------------------
# Base de datos relacional gestionada: Amazon RDS for MySQL 8.4
# AWS administra el motor, los parches y el almacenamiento; nosotros solo la declaramos.
# El log de errores y el de consultas lentas se publican en CloudWatch Logs.
# ---------------------------------------------------------------------------

locals {
  identifier = "${var.project_name}-mysql"
  log_types  = ["error", "slowquery"]
}

# Grupos de logs creados antes que la instancia, para fijar su retencion
# (si los crea RDS, quedan sin fecha de expiracion)
resource "aws_cloudwatch_log_group" "rds" {
  for_each = toset(local.log_types)

  name              = "/aws/rds/instance/${local.identifier}/${each.key}"
  retention_in_days = var.log_retention_days
}

# Parametros de MySQL: registra las consultas que tardan mas de 1 segundo
resource "aws_db_parameter_group" "mysql" {
  name        = "${var.project_name}-mysql84"
  family      = "mysql8.4"
  description = "MySQL 8.4 para Joomla con log de consultas lentas"

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "1"
  }

  parameter {
    name  = "log_output"
    value = "FILE"
  }
}

resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-db-subnets"
  description = "Subredes privadas para RDS"
  subnet_ids  = var.private_subnet_ids

  tags = { Name = "${var.project_name}-db-subnets" }
}

resource "aws_db_instance" "mysql" {
  identifier     = local.identifier
  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.mysql.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false # Solo accesible desde dentro de la VPC
  multi_az               = false # Una sola zona para el laboratorio (menor costo)

  # Configuracion de laboratorio: sin respaldos ni snapshot final para crear y destruir rapido
  backup_retention_period    = 0
  skip_final_snapshot        = true
  delete_automated_backups   = true
  deletion_protection        = false
  apply_immediately          = true
  auto_minor_version_upgrade = true

  enabled_cloudwatch_logs_exports = local.log_types

  tags = { Name = local.identifier }

  depends_on = [aws_cloudwatch_log_group.rds]
}
