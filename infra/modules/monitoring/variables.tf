variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "alert_email" {
  description = "Correo suscrito al tema SNS de alertas; vacio = sin suscripcion"
  type        = string
}

variable "alb_dns_name" {
  type = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "service_name" {
  type = string
}

variable "service_arn" {
  type = string
}

variable "app_log_group_name" {
  type = string
}

variable "db_instance_id" {
  type = string
}

variable "db_log_groups" {
  type = list(string)
}

variable "cache_cluster_id" {
  type = string
}

variable "cache_log_group" {
  type = string
}

variable "alb_5xx_per_minute_threshold" {
  type = number
}

variable "latency_p95_seconds_threshold" {
  type = number
}

variable "php_fatal_per_minute_threshold" {
  type = number
}

variable "db_max_connections_threshold" {
  type = number
}
