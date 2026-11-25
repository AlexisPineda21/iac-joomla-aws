# Valores no secretos del ambiente unico (prod). Las contrasenas las genera Terraform
# (random_password) y el correo de alertas llega como secreto (TF_VAR_alert_email).
aws_region   = "us-east-1"
project_name = "joomla-ecs"

vpc_cidr             = "10.20.0.0/16"
public_subnet_cidrs  = ["10.20.1.0/24", "10.20.2.0/24"]
private_subnet_cidrs = ["10.20.11.0/24", "10.20.12.0/24"]

ecr_repository_name = "joomla-app"
image_tag           = "latest"
task_cpu            = 512
task_memory         = 1024
desired_count       = 1

db_instance_class    = "db.t4g.micro"
db_engine_version    = "8.4"
db_allocated_storage = 20

cache_node_type      = "cache.t4g.micro"
cache_engine_version = "8.0"

site_name = "Joomla en AWS - Actividad 6"

# Observabilidad
log_retention_days             = 14
fault_injection_enabled        = true # Permite /health.php?simulate=error|fatal para probar las alarmas
alb_5xx_per_minute_threshold   = 10
latency_p95_seconds_threshold  = 2
php_fatal_per_minute_threshold = 5
db_max_connections_threshold   = 60
