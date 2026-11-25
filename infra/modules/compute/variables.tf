variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "app_security_group_id" {
  type = string
}

variable "image" {
  description = "Imagen del contenedor (repositorio ECR y tag)"
  type        = string
}

variable "task_cpu" {
  type = number
}

variable "task_memory" {
  type = number
}

variable "desired_count" {
  type = number
}

variable "fault_injection_enabled" {
  type = bool
}

variable "log_retention_days" {
  type = number
}

variable "db_host" {
  type = string
}

variable "db_port" {
  type = number
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "cache_host" {
  type = string
}

variable "cache_port" {
  type = number
}

variable "efs_file_system_id" {
  type = string
}

variable "efs_access_point_id" {
  type = string
}

variable "site_name" {
  type = string
}

variable "admin_name" {
  type = string
}

variable "admin_username" {
  type = string
}

variable "admin_email" {
  type = string
}

variable "admin_password" {
  type      = string
  sensitive = true
}
