# ---------------------------------------------------------------------------
# Observabilidad con Amazon CloudWatch
#   Metricas: ALB, ECS, RDS y ElastiCache (gratuitas) + metricas propias desde los logs
#   Logs:     filtros de metricas y consultas guardadas de Logs Insights
#   Alertas:  alarmas -> tema SNS -> correo; eventos de despliegue de ECS -> SNS
#   Externo:  health check de Route 53 contra /health.php desde varias regiones
#   Tablero:  dashboard.tf
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  namespace     = "Joomla/${var.project_name}"
  alarm_actions = [aws_sns_topic.alerts.arn]

  alb_dimensions   = { LoadBalancer = var.alb_arn_suffix }
  tg_dimensions    = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
  ecs_dimensions   = { ClusterName = var.cluster_name, ServiceName = var.service_name }
  rds_dimensions   = { DBInstanceIdentifier = var.db_instance_id }
  cache_dimensions = { CacheClusterId = var.cache_cluster_id }

  # Las metricas de los health checks de Route 53 solo se publican en us-east-1
  route53_alarm_enabled = var.aws_region == "us-east-1"
}

# ---------------------------------------------------------------------------
# Notificaciones
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

# AWS envia un correo para confirmar la suscripcion; hasta aceptarlo no llegan alertas
resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Quien puede publicar en el tema: las alarmas de CloudWatch y las reglas de EventBridge
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountOwner"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = ["sns:Publish", "sns:Subscribe", "sns:GetTopicAttributes", "sns:SetTopicAttributes"]
        Resource  = aws_sns_topic.alerts.arn
      },
      {
        Sid       = "CloudWatchAndEventBridge"
        Effect    = "Allow"
        Principal = { Service = ["cloudwatch.amazonaws.com", "events.amazonaws.com"] }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Health check externo: Route 53 consulta /health.php desde varias regiones
# ---------------------------------------------------------------------------
resource "aws_route53_health_check" "site" {
  type              = "HTTP"
  fqdn              = var.alb_dns_name
  port              = 80
  resource_path     = "/health.php"
  request_interval  = 30
  failure_threshold = 3
  measure_latency   = true

  tags = { Name = "${var.project_name}-health" }
}

# ---------------------------------------------------------------------------
# Metricas a partir de los logs del contenedor
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "php_fatal" {
  name           = "${var.project_name}-php-fatal-errors"
  log_group_name = var.app_log_group_name
  pattern        = "\"PHP Fatal error\""

  metric_transformation {
    name          = "PHPFatalErrors"
    namespace     = local.namespace
    value         = "1"
    default_value = "0"
  }
}

# Cada arranque del contenedor (despliegues, reinicios, escalado)
resource "aws_cloudwatch_log_metric_filter" "container_starts" {
  name           = "${var.project_name}-container-starts"
  log_group_name = var.app_log_group_name
  pattern        = "\"[start-joomla] Iniciando Apache\""

  metric_transformation {
    name          = "ContainerStarts"
    namespace     = local.namespace
    value         = "1"
    default_value = "0"
  }
}

# ---------------------------------------------------------------------------
# Alarmas - BACKEND (balanceador, contenedores y aplicacion)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "site_down" {
  count = local.route53_alarm_enabled ? 1 : 0

  alarm_name          = "${var.project_name}-backend-sitio-caido"
  alarm_description   = "Route 53 no recibe 200 de /health.php desde sus regiones durante 2 minutos. Revisar tareas de ECS, eventos del servicio y logs /ecs/${var.project_name}."
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  dimensions          = { HealthCheckId = aws_route53_health_check.site.id }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.project_name}-backend-errores-5xx-joomla"
  alarm_description   = "Joomla respondio mas de ${var.alb_5xx_per_minute_threshold} errores 5xx en un minuto. Revisar errores PHP en Logs Insights y la conexion a RDS/Valkey."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = local.alb_dimensions
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alb_5xx_per_minute_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "elb_5xx" {
  alarm_name          = "${var.project_name}-backend-errores-5xx-balanceador"
  alarm_description   = "El ALB genero mas de ${var.alb_5xx_per_minute_threshold} errores 5xx propios (502/503/504) en un minuto: no hay tareas sanas o no responden a tiempo."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  dimensions          = local.alb_dimensions
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alb_5xx_per_minute_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  alarm_name          = "${var.project_name}-backend-latencia-p95"
  alarm_description   = "La latencia p95 de Joomla supera ${var.latency_p95_seconds_threshold} s durante 5 minutos. Revisar CPU de ECS, consultas lentas de RDS y tasa de aciertos de Valkey."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = local.alb_dimensions
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.latency_p95_seconds_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "no_healthy_targets" {
  alarm_name          = "${var.project_name}-backend-sin-tareas-sanas"
  alarm_description   = "El target group no tiene tareas sanas durante 3 minutos. Revisar eventos del servicio ECS y el health check /health.php."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  dimensions          = local.tg_dimensions
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name          = "${var.project_name}-backend-cpu-ecs"
  alarm_description   = "CPU promedio del servicio ECS sobre 80 % durante 5 minutos. Considerar mas tareas (desired_count) o mas CPU (task_cpu)."
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = local.ecs_dimensions
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  alarm_name          = "${var.project_name}-backend-memoria-ecs"
  alarm_description   = "Memoria promedio del servicio ECS sobre 85 % durante 5 minutos. Riesgo de que el contenedor se reinicie por falta de memoria."
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  dimensions          = local.ecs_dimensions
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  comparison_operator = "GreaterThanThreshold"
  threshold           = 85
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "php_fatal" {
  alarm_name          = "${var.project_name}-backend-errores-fatales-php"
  alarm_description   = "Mas de ${var.php_fatal_per_minute_threshold} errores fatales de PHP en un minuto. Ver la consulta guardada ${var.project_name}/errores-php en Logs Insights."
  namespace           = local.namespace
  metric_name         = aws_cloudwatch_log_metric_filter.php_fatal.metric_transformation[0].name
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.php_fatal_per_minute_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# Despliegues de ECS: avisa cuando uno termina o falla (circuit breaker con rollback)
resource "aws_cloudwatch_event_rule" "deployments" {
  name        = "${var.project_name}-ecs-deployments"
  description = "Despliegues completados o fallidos del servicio ${var.service_name}"

  event_pattern = jsonencode({
    source        = ["aws.ecs"]
    "detail-type" = ["ECS Deployment State Change"]
    resources     = [var.service_arn]
    detail = {
      eventName = ["SERVICE_DEPLOYMENT_COMPLETED", "SERVICE_DEPLOYMENT_FAILED"]
    }
  })
}

resource "aws_cloudwatch_event_target" "deployments" {
  rule      = aws_cloudwatch_event_rule.deployments.name
  target_id = "sns-alerts"
  arn       = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      event      = "$.detail.eventName"
      deployment = "$.detail.deploymentId"
      reason     = "$.detail.reason"
      time       = "$.time"
    }
    input_template = "\"ECS ${var.service_name}: <event> (<deployment>) a las <time> UTC. <reason>\""
  }
}

# ---------------------------------------------------------------------------
# Alarmas - BASES DE DATOS (RDS MySQL y ElastiCache Valkey)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project_name}-db-cpu-rds"
  alarm_description   = "CPU de RDS MySQL sobre 80 % durante 10 minutos. Revisar el log de consultas lentas."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = local.rds_dimensions
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.project_name}-db-disco-rds"
  alarm_description   = "Quedan menos de 2 GB libres en RDS. Aumentar db_allocated_storage."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = local.rds_dimensions
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  threshold           = 2 * 1024 * 1024 * 1024
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.project_name}-db-conexiones-rds"
  alarm_description   = "Mas de ${var.db_max_connections_threshold} conexiones a MySQL durante 5 minutos (cerca del maximo de db.t4g.micro)."
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  dimensions          = local.rds_dimensions
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.db_max_connections_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "rds_memory" {
  alarm_name          = "${var.project_name}-db-memoria-rds"
  alarm_description   = "Menos de 64 MB de memoria libre en RDS durante 10 minutos."
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  dimensions          = local.rds_dimensions
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 64 * 1024 * 1024
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "valkey_cpu" {
  alarm_name          = "${var.project_name}-db-cpu-valkey"
  alarm_description   = "CPU del motor de Valkey sobre 80 % durante 10 minutos."
  namespace           = "AWS/ElastiCache"
  metric_name         = "EngineCPUUtilization"
  dimensions          = local.cache_dimensions
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "valkey_memory" {
  alarm_name          = "${var.project_name}-db-memoria-valkey"
  alarm_description   = "Valkey usa mas del 85 % de su memoria durante 10 minutos: empezara a expulsar claves (cache y sesiones)."
  namespace           = "AWS/ElastiCache"
  metric_name         = "DatabaseMemoryUsagePercentage"
  dimensions          = local.cache_dimensions
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 85
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ---------------------------------------------------------------------------
# Consultas guardadas de CloudWatch Logs Insights
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_query_definition" "php_errors" {
  name            = "${var.project_name}/errores-php"
  log_group_names = [var.app_log_group_name]
  query_string    = <<-EOT
    fields @timestamp, @logStream, @message
    | filter @message like /PHP (Fatal error|Parse error|Warning)/
    | sort @timestamp desc
    | limit 50
  EOT
}

resource "aws_cloudwatch_query_definition" "http_5xx" {
  name            = "${var.project_name}/peticiones-5xx"
  log_group_names = [var.app_log_group_name]
  query_string    = <<-EOT
    parse @message /"(?<method>[A-Z]+) (?<path>[^ ]+) [^"]*" (?<status>\d{3}) /
    | filter status >= 500
    | stats count(*) as errores by path, status
    | sort errores desc
  EOT
}

resource "aws_cloudwatch_query_definition" "top_paths" {
  name            = "${var.project_name}/paginas-mas-visitadas"
  log_group_names = [var.app_log_group_name]
  query_string    = <<-EOT
    parse @message /"(?<method>[A-Z]+) (?<path>[^ ]+) [^"]*" (?<status>\d{3}) /
    | filter ispresent(path) and path not like /health.php/
    | stats count(*) as visitas by path
    | sort visitas desc
    | limit 20
  EOT
}

resource "aws_cloudwatch_query_definition" "startup" {
  name            = "${var.project_name}/arranques-del-contenedor"
  log_group_names = [var.app_log_group_name]
  query_string    = <<-EOT
    fields @timestamp, @logStream, @message
    | filter @message like /\[start-joomla\]|\[configure-joomla\]|Joomla has been installed/
    | sort @timestamp desc
    | limit 50
  EOT
}

resource "aws_cloudwatch_query_definition" "mysql_slow_queries" {
  name            = "${var.project_name}/consultas-lentas-mysql"
  log_group_names = [for group in var.db_log_groups : group if endswith(group, "/slowquery")]
  query_string    = <<-EOT
    fields @timestamp, @message
    | sort @timestamp desc
    | limit 50
  EOT
}

resource "aws_cloudwatch_query_definition" "mysql_errors" {
  name            = "${var.project_name}/errores-mysql"
  log_group_names = [for group in var.db_log_groups : group if endswith(group, "/error")]
  query_string    = <<-EOT
    fields @timestamp, @message
    | filter @message like /\[(ERROR|Warning)\]/
    | sort @timestamp desc
    | limit 50
  EOT
}

resource "aws_cloudwatch_query_definition" "valkey_slow_log" {
  name            = "${var.project_name}/comandos-lentos-valkey"
  log_group_names = [var.cache_log_group]
  query_string    = <<-EOT
    fields @timestamp, @message
    | sort @timestamp desc
    | limit 50
  EOT
}
