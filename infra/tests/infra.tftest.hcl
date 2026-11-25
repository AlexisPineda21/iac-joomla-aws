# Pruebas de la IaC sin tocar AWS: los proveedores son simulados (mock_provider), asi
# que cada "run" crea los recursos solo en memoria. Se ejecutan en el pipeline con:
#   terraform test

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
  mock_data "aws_ecr_repository" {
    defaults = { repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/joomla-app" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_elasticache_replication_group" {
    defaults = { member_clusters = ["joomla-ecs-valkey-001"] }
  }
  # Los ARN simulados deben tener formato de ARN para pasar las validaciones del proveedor
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:us-east-1:123456789012:joomla-ecs-alerts" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/mock/1" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/mock/1" }
  }
  mock_resource "aws_ssm_parameter" {
    defaults = { arn = "arn:aws:ssm:us-east-1:123456789012:parameter/mock" }
  }
  mock_resource "aws_ecs_service" {
    defaults = { arn = "arn:aws:ecs:us-east-1:123456789012:service/joomla-ecs-cluster/joomla-ecs-service" }
  }
}

mock_provider "random" {}

run "stack_completo" {
  command = apply

  assert {
    condition     = endswith(output.health_url, "/health.php")
    error_message = "El sitio debe exponer /health.php"
  }

  assert {
    condition     = length(output.alarm_names) == 14
    error_message = "Se esperaban 14 alarmas de CloudWatch en us-east-1"
  }
}

run "servicio_ecs_sin_caida_y_con_rollback" {
  command = apply

  module {
    source = "./modules/compute"
  }

  variables {
    project_name            = "joomla-ecs"
    aws_region              = "us-east-1"
    vpc_id                  = "vpc-123"
    public_subnet_ids       = ["subnet-a", "subnet-b"]
    alb_security_group_id   = "sg-alb"
    app_security_group_id   = "sg-app"
    image                   = "123456789012.dkr.ecr.us-east-1.amazonaws.com/joomla-app:latest"
    task_cpu                = 512
    task_memory             = 1024
    desired_count           = 1
    fault_injection_enabled = false
    log_retention_days      = 14
    db_host                 = "db.example.internal"
    db_port                 = 3306
    db_name                 = "joomladb"
    db_username             = "joomlauser"
    db_password             = "ClaveDePrueba123456789"
    cache_host              = "cache.example.internal"
    cache_port              = 6379
    efs_file_system_id      = "fs-123"
    efs_access_point_id     = "fsap-123"
    site_name               = "Prueba"
    admin_name              = "Administrador"
    admin_username          = "admin"
    admin_email             = "admin@example.com"
    admin_password          = "ClaveAdminPrueba123"
  }

  assert {
    condition     = aws_ecs_service.joomla.deployment_minimum_healthy_percent == 100 && aws_ecs_service.joomla.deployment_maximum_percent == 200
    error_message = "El despliegue debe ser rolling sin caida (100 % / 200 %)"
  }

  assert {
    condition     = aws_ecs_service.joomla.deployment_circuit_breaker[0].enable && aws_ecs_service.joomla.deployment_circuit_breaker[0].rollback
    error_message = "El circuit breaker con rollback debe estar activo"
  }

  assert {
    condition     = aws_lb_target_group.joomla.health_check[0].path == "/health.php"
    error_message = "El health check del ALB debe usar /health.php"
  }

  assert {
    condition     = !strcontains(aws_ecs_task_definition.joomla.container_definitions, var.db_password) && !strcontains(aws_ecs_task_definition.joomla.container_definitions, var.admin_password)
    error_message = "Las contrasenas no pueden ir en texto plano en la definicion de tarea"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.joomla.container_definitions, "\"FAULT_INJECTION\",\"value\":\"disabled\"")
    error_message = "La inyeccion de fallas debe quedar apagada por defecto"
  }
}

run "alarma_route53_solo_en_us_east_1" {
  command = apply

  variables {
    aws_region = "us-west-2"
  }

  assert {
    condition     = length(output.alarm_names) == 13
    error_message = "Fuera de us-east-1 no se crea la alarma del health check de Route 53"
  }
}
