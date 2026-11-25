output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.main.dashboard_name
}

output "health_check_id" {
  value = aws_route53_health_check.site.id
}

output "alarm_names" {
  value = concat(
    aws_cloudwatch_metric_alarm.site_down[*].alarm_name,
    [
      aws_cloudwatch_metric_alarm.target_5xx.alarm_name,
      aws_cloudwatch_metric_alarm.elb_5xx.alarm_name,
      aws_cloudwatch_metric_alarm.latency_p95.alarm_name,
      aws_cloudwatch_metric_alarm.no_healthy_targets.alarm_name,
      aws_cloudwatch_metric_alarm.ecs_cpu.alarm_name,
      aws_cloudwatch_metric_alarm.ecs_memory.alarm_name,
      aws_cloudwatch_metric_alarm.php_fatal.alarm_name,
      aws_cloudwatch_metric_alarm.rds_cpu.alarm_name,
      aws_cloudwatch_metric_alarm.rds_storage.alarm_name,
      aws_cloudwatch_metric_alarm.rds_connections.alarm_name,
      aws_cloudwatch_metric_alarm.rds_memory.alarm_name,
      aws_cloudwatch_metric_alarm.valkey_cpu.alarm_name,
      aws_cloudwatch_metric_alarm.valkey_memory.alarm_name,
    ]
  )
}
