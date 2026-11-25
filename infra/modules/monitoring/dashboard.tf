# ---------------------------------------------------------------------------
# Dashboard de CloudWatch, organizado por capas: trafico, contenedores, logs,
# base de datos relacional, base de datos en memoria y estado de las alarmas.
# Cada fila es una lista de widgets; las posiciones (x, y) se calculan abajo.
# ---------------------------------------------------------------------------

locals {
  alb_dims   = ["LoadBalancer", var.alb_arn_suffix]
  tg_dims    = ["TargetGroup", var.target_group_arn_suffix, "LoadBalancer", var.alb_arn_suffix]
  ecs_dims   = ["ClusterName", var.cluster_name, "ServiceName", var.service_name]
  rds_dims   = ["DBInstanceIdentifier", var.db_instance_id]
  cache_dims = ["CacheClusterId", var.cache_cluster_id]

  alarm_arns = concat(
    aws_cloudwatch_metric_alarm.site_down[*].arn,
    [
      aws_cloudwatch_metric_alarm.target_5xx.arn,
      aws_cloudwatch_metric_alarm.elb_5xx.arn,
      aws_cloudwatch_metric_alarm.latency_p95.arn,
      aws_cloudwatch_metric_alarm.no_healthy_targets.arn,
      aws_cloudwatch_metric_alarm.ecs_cpu.arn,
      aws_cloudwatch_metric_alarm.ecs_memory.arn,
      aws_cloudwatch_metric_alarm.php_fatal.arn,
      aws_cloudwatch_metric_alarm.rds_cpu.arn,
      aws_cloudwatch_metric_alarm.rds_storage.arn,
      aws_cloudwatch_metric_alarm.rds_connections.arn,
      aws_cloudwatch_metric_alarm.rds_memory.arn,
      aws_cloudwatch_metric_alarm.valkey_cpu.arn,
      aws_cloudwatch_metric_alarm.valkey_memory.arn,
    ]
  )

  dashboard_rows = [
    [{ type = "text", width = 24, height = 1, properties = { markdown = "## Disponibilidad y trafico (Route 53 y ALB)" } }],
    [
      {
        type = "metric", width = 8, height = 6
        properties = {
          title   = "Health check de Route 53 (1 = OK)", region = "us-east-1", view = "timeSeries", period = 60
          metrics = [["AWS/Route53", "HealthCheckStatus", "HealthCheckId", aws_route53_health_check.site.id, { stat = "Minimum", label = "Estado" }]]
          yAxis   = { left = { min = 0, max = 1 } }
        }
      },
      {
        type = "metric", width = 8, height = 6
        properties = {
          title = "Peticiones por codigo de respuesta", region = var.aws_region, view = "timeSeries", stacked = true, period = 60
          metrics = [
            concat(["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count"], local.alb_dims, [{ stat = "Sum", label = "2xx" }]),
            concat(["AWS/ApplicationELB", "HTTPCode_Target_3XX_Count"], local.alb_dims, [{ stat = "Sum", label = "3xx" }]),
            concat(["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count"], local.alb_dims, [{ stat = "Sum", label = "4xx" }]),
            concat(["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count"], local.alb_dims, [{ stat = "Sum", label = "5xx Joomla" }]),
            concat(["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count"], local.alb_dims, [{ stat = "Sum", label = "5xx ALB" }]),
          ]
        }
      },
      {
        type = "metric", width = 8, height = 6
        properties = {
          title = "Latencia de Joomla (segundos)", region = var.aws_region, view = "timeSeries", period = 60
          metrics = [
            concat(["AWS/ApplicationELB", "TargetResponseTime"], local.alb_dims, [{ stat = "p50", label = "p50" }]),
            concat(["AWS/ApplicationELB", "TargetResponseTime"], local.alb_dims, [{ stat = "p95", label = "p95" }]),
            concat(["AWS/ApplicationELB", "TargetResponseTime"], local.alb_dims, [{ stat = "p99", label = "p99" }]),
          ]
          annotations = { horizontal = [{ label = "Umbral alarma p95", value = var.latency_p95_seconds_threshold }] }
        }
      },
    ],
    [{ type = "text", width = 24, height = 1, properties = { markdown = "## Contenedores (ECS Fargate)" } }],
    [
      {
        type = "metric", width = 8, height = 6
        properties = {
          title = "Tareas sanas y no sanas en el balanceador", region = var.aws_region, view = "timeSeries", period = 60
          metrics = [
            concat(["AWS/ApplicationELB", "HealthyHostCount"], local.tg_dims, [{ stat = "Minimum", label = "Sanas" }]),
            concat(["AWS/ApplicationELB", "UnHealthyHostCount"], local.tg_dims, [{ stat = "Maximum", label = "No sanas" }]),
          ]
        }
      },
      {
        type = "metric", width = 8, height = 6
        properties = {
          title = "CPU y memoria del servicio (%)", region = var.aws_region, view = "timeSeries", period = 60
          metrics = [
            concat(["AWS/ECS", "CPUUtilization"], local.ecs_dims, [{ stat = "Average", label = "CPU" }]),
            concat(["AWS/ECS", "MemoryUtilization"], local.ecs_dims, [{ stat = "Average", label = "Memoria" }]),
          ]
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric", width = 8, height = 6
        properties = {
          title = "Arranques del contenedor y errores fatales de PHP", region = var.aws_region, view = "timeSeries", period = 60
          metrics = [
            [local.namespace, "ContainerStarts", { stat = "Sum", label = "Arranques (despliegues)" }],
            [local.namespace, "PHPFatalErrors", { stat = "Sum", label = "PHP Fatal error" }],
          ]
        }
      },
    ],
    [
      {
        type = "log", width = 24, height = 6
        properties = {
          title  = "Ultimos errores y arranques (logs del contenedor)"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${var.app_log_group_name}' | fields @timestamp, @message | filter @message like /PHP (Fatal error|Warning)|\\[start-joomla\\]/ | sort @timestamp desc | limit 20"
        }
      },
    ],
    [{ type = "text", width = 24, height = 1, properties = { markdown = "## Base de datos relacional (RDS for MySQL)" } }],
    [
      {
        type = "metric", width = 8, height = 6
        properties = {
          title   = "CPU (%)", region = var.aws_region, view = "timeSeries", period = 60
          metrics = [concat(["AWS/RDS", "CPUUtilization"], local.rds_dims, [{ stat = "Average", label = "CPU" }])]
          yAxis   = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric", width = 8, height = 6
        properties = {
          title   = "Conexiones", region = var.aws_region, view = "timeSeries", period = 60
          metrics = [concat(["AWS/RDS", "DatabaseConnections"], local.rds_dims, [{ stat = "Maximum", label = "Conexiones" }])]
        }
      },
      {
        type = "metric", width = 8, height = 6
        properties = {
          title = "Memoria y disco libres (bytes)", region = var.aws_region, view = "timeSeries", period = 300
          metrics = [
            concat(["AWS/RDS", "FreeableMemory"], local.rds_dims, [{ stat = "Average", label = "Memoria libre" }]),
            concat(["AWS/RDS", "FreeStorageSpace"], local.rds_dims, [{ stat = "Minimum", label = "Disco libre", yAxis = "right" }]),
          ]
        }
      },
    ],
    [
      {
        type = "metric", width = 8, height = 6
        properties = {
          title = "IOPS de lectura y escritura", region = var.aws_region, view = "timeSeries", period = 60
          metrics = [
            concat(["AWS/RDS", "ReadIOPS"], local.rds_dims, [{ stat = "Average", label = "Lectura" }]),
            concat(["AWS/RDS", "WriteIOPS"], local.rds_dims, [{ stat = "Average", label = "Escritura" }]),
          ]
        }
      },
      {
        type = "metric", width = 8, height = 6
        properties = {
          title = "Latencia de disco (segundos)", region = var.aws_region, view = "timeSeries", period = 60
          metrics = [
            concat(["AWS/RDS", "ReadLatency"], local.rds_dims, [{ stat = "Average", label = "Lectura" }]),
            concat(["AWS/RDS", "WriteLatency"], local.rds_dims, [{ stat = "Average", label = "Escritura" }]),
          ]
        }
      },
      {
        type = "metric", width = 8, height = 6
        properties = {
          title = "Trafico de red (bytes/s)", region = var.aws_region, view = "timeSeries", period = 60
          metrics = [
            concat(["AWS/RDS", "NetworkReceiveThroughput"], local.rds_dims, [{ stat = "Average", label = "Recibido" }]),
            concat(["AWS/RDS", "NetworkTransmitThroughput"], local.rds_dims, [{ stat = "Average", label = "Enviado" }]),
          ]
        }
      },
    ],
    [{ type = "text", width = 24, height = 1, properties = { markdown = "## Base de datos en memoria (ElastiCache for Valkey)" } }],
    [
      {
        type = "metric", width = 8, height = 6
        properties = {
          title = "CPU del motor y memoria usada (%)", region = var.aws_region, view = "timeSeries", period = 60
          metrics = [
            concat(["AWS/ElastiCache", "EngineCPUUtilization"], local.cache_dims, [{ stat = "Average", label = "CPU" }]),
            concat(["AWS/ElastiCache", "DatabaseMemoryUsagePercentage"], local.cache_dims, [{ stat = "Average", label = "Memoria" }]),
          ]
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric", width = 8, height = 6
        properties = {
          title = "Aciertos y fallos de cache", region = var.aws_region, view = "timeSeries", period = 60
          metrics = [
            concat(["AWS/ElastiCache", "CacheHits"], local.cache_dims, [{ stat = "Sum", label = "Aciertos" }]),
            concat(["AWS/ElastiCache", "CacheMisses"], local.cache_dims, [{ stat = "Sum", label = "Fallos" }]),
            concat(["AWS/ElastiCache", "CacheHitRate"], local.cache_dims, [{ stat = "Average", label = "Tasa de aciertos (%)", yAxis = "right" }]),
          ]
        }
      },
      {
        type = "metric", width = 8, height = 6
        properties = {
          title = "Conexiones, claves y expulsiones", region = var.aws_region, view = "timeSeries", period = 60
          metrics = [
            concat(["AWS/ElastiCache", "CurrConnections"], local.cache_dims, [{ stat = "Maximum", label = "Conexiones" }]),
            concat(["AWS/ElastiCache", "CurrItems"], local.cache_dims, [{ stat = "Maximum", label = "Claves" }]),
            concat(["AWS/ElastiCache", "Evictions"], local.cache_dims, [{ stat = "Sum", label = "Expulsiones" }]),
          ]
        }
      },
    ],
    [{ type = "text", width = 24, height = 1, properties = { markdown = "## Estado de las alarmas" } }],
    [
      {
        type = "alarm", width = 24, height = 5
        properties = {
          title  = "Alarmas (backend y bases de datos)"
          alarms = local.alarm_arns
        }
      },
    ],
  ]

  # y de cada fila = suma de las alturas de las filas anteriores
  row_heights = [for row in local.dashboard_rows : max([for widget in row : widget.height]...)]
  row_y       = [for i in range(length(local.dashboard_rows)) : sum(concat([0], slice(local.row_heights, 0, i)))]

  # x de cada widget = suma de los anchos de los widgets anteriores en su fila
  dashboard_widgets = flatten([
    for i, row in local.dashboard_rows : [
      for j, widget in row : merge(widget, {
        x = sum(concat([0], [for k in range(j) : row[k].width]))
        y = local.row_y[i]
      })
    ]
  ])
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = var.project_name
  dashboard_body = jsonencode({ widgets = local.dashboard_widgets })
}
