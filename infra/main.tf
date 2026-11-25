# ---------------------------------------------------------------------------
# Joomla en AWS con servicios contenerizados, dos bases de datos gestionadas,
# CI/CD en GitHub Actions y observabilidad en CloudWatch
#
#   Internet -> ALB -> ECS Fargate (imagen del fork joomla-app, desde ECR)
#                         |-- Amazon RDS for MySQL       (base de datos relacional)
#                         |-- Amazon ElastiCache Valkey  (base de datos en memoria: cache y sesiones)
#                         '-- Amazon EFS                 (configuration.php e imagenes)
#   CloudWatch: logs, metricas, alarmas -> SNS (correo), dashboard; Route 53 health check
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

# Repositorio creado por bootstrap; la imagen la publica el pipeline de joomla-app
data "aws_ecr_repository" "app" {
  name = var.ecr_repository_name
}

locals {
  # Dos zonas de disponibilidad: el ALB, RDS y ElastiCache exigen subredes en al menos dos
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# Contrasenas generadas por Terraform: no las escribe nadie ni quedan en el repositorio.
# Se guardan en el estado (cifrado en S3) y en SSM Parameter Store como SecureString.
resource "random_password" "db" {
  length  = 24
  special = false
}

resource "random_password" "admin" {
  length  = 20
  special = false
}

module "networking" {
  source = "./modules/networking"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  http_allowed_cidrs   = var.http_allowed_cidrs
}

# Base de datos relacional gestionada: el contenido del sitio (articulos, usuarios, menus...)
module "database" {
  source = "./modules/database"

  project_name       = var.project_name
  private_subnet_ids = module.networking.private_subnet_ids
  security_group_id  = module.networking.db_security_group_id
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = random_password.db.result
  instance_class     = var.db_instance_class
  engine_version     = var.db_engine_version
  allocated_storage  = var.db_allocated_storage
  log_retention_days = var.log_retention_days
}

# Base de datos en memoria gestionada: cache y sesiones de Joomla
module "cache" {
  source = "./modules/cache"

  project_name       = var.project_name
  private_subnet_ids = module.networking.private_subnet_ids
  security_group_id  = module.networking.cache_security_group_id
  node_type          = var.cache_node_type
  engine_version     = var.cache_engine_version
  log_retention_days = var.log_retention_days
}

# Almacenamiento persistente: configuration.php e images/ (el codigo viaja en la imagen)
module "storage" {
  source = "./modules/storage"

  project_name       = var.project_name
  private_subnet_ids = module.networking.private_subnet_ids
  security_group_id  = module.networking.efs_security_group_id
}

# Servicio contenerizado: cluster ECS, tarea Fargate con Joomla y balanceador de carga
module "compute" {
  source = "./modules/compute"

  project_name          = var.project_name
  aws_region            = var.aws_region
  vpc_id                = module.networking.vpc_id
  public_subnet_ids     = module.networking.public_subnet_ids
  alb_security_group_id = module.networking.alb_security_group_id
  app_security_group_id = module.networking.app_security_group_id

  image                   = "${data.aws_ecr_repository.app.repository_url}:${var.image_tag}"
  task_cpu                = var.task_cpu
  task_memory             = var.task_memory
  desired_count           = var.desired_count
  fault_injection_enabled = var.fault_injection_enabled
  log_retention_days      = var.log_retention_days

  db_host     = module.database.address
  db_port     = module.database.port
  db_name     = var.db_name
  db_username = var.db_username
  db_password = random_password.db.result

  cache_host = module.cache.primary_endpoint
  cache_port = module.cache.port

  efs_file_system_id  = module.storage.file_system_id
  efs_access_point_id = module.storage.access_point_id

  site_name      = var.site_name
  admin_name     = var.admin_name
  admin_username = var.admin_username
  admin_email    = var.admin_email
  admin_password = random_password.admin.result

  # La tarea solo arranca cuando los puntos de montaje de EFS estan listos
  depends_on = [module.storage]
}

# Observabilidad: alarmas, notificaciones, health check externo, dashboard y consultas
module "monitoring" {
  source = "./modules/monitoring"

  project_name = var.project_name
  aws_region   = var.aws_region
  alert_email  = var.alert_email

  alb_dns_name            = module.compute.alb_dns_name
  alb_arn_suffix          = module.compute.alb_arn_suffix
  target_group_arn_suffix = module.compute.target_group_arn_suffix
  cluster_name            = module.compute.cluster_name
  service_name            = module.compute.service_name
  service_arn             = module.compute.service_arn
  app_log_group_name      = module.compute.log_group_name

  db_instance_id   = module.database.instance_id
  db_log_groups    = module.database.log_group_names
  cache_cluster_id = module.cache.member_cluster_id
  cache_log_group  = module.cache.log_group_name

  alb_5xx_per_minute_threshold   = var.alb_5xx_per_minute_threshold
  latency_p95_seconds_threshold  = var.latency_p95_seconds_threshold
  php_fatal_per_minute_threshold = var.php_fatal_per_minute_threshold
  db_max_connections_threshold   = var.db_max_connections_threshold
}
