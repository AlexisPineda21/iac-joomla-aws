# ---------------------------------------------------------------------------
# Generales
# ---------------------------------------------------------------------------
variable "aws_region" {
  description = "Region de AWS donde se crea la infraestructura"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo para nombrar los recursos (minusculas, numeros y guiones)"
  type        = string
  default     = "joomla-ecs"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,18}[a-z0-9]$", var.project_name))
    error_message = "project_name debe tener entre 4 y 20 caracteres: minusculas, numeros y guiones."
  }
}

# ---------------------------------------------------------------------------
# Red
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "Rango de direcciones de la VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Subredes publicas (balanceador y tareas de ECS), una por zona de disponibilidad"
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Subredes privadas (RDS, ElastiCache y EFS), una por zona de disponibilidad"
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24"]
}

variable "http_allowed_cidrs" {
  description = "Rangos que pueden entrar por HTTP al balanceador"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------
# Contenedor (ECS Fargate)
# ---------------------------------------------------------------------------
variable "ecr_repository_name" {
  description = "Repositorio de ECR con la imagen del fork de Joomla (lo crea bootstrap)"
  type        = string
  default     = "joomla-app"
}

variable "image_tag" {
  description = "Tag de la imagen. El pipeline de la aplicacion mueve 'latest' y fuerza un despliegue nuevo"
  type        = string
  default     = "latest"
}

variable "task_cpu" {
  description = "CPU de la tarea de Fargate (512 = 0,5 vCPU)"
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Memoria de la tarea de Fargate en MiB"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Numero de contenedores de Joomla que deben estar corriendo"
  type        = number
  default     = 1
}

variable "fault_injection_enabled" {
  description = "Habilita /health.php?simulate=error|fatal para probar las alarmas"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Dias que se conservan los logs en CloudWatch"
  type        = number
  default     = 14
}

# ---------------------------------------------------------------------------
# Base de datos relacional (Amazon RDS for MySQL)
# ---------------------------------------------------------------------------
variable "db_name" {
  description = "Nombre de la base de datos de Joomla"
  type        = string
  default     = "joomladb"
}

variable "db_username" {
  description = "Usuario administrador de la base de datos"
  type        = string
  default     = "joomlauser"
}

variable "db_instance_class" {
  description = "Tipo de instancia de RDS"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_engine_version" {
  description = "Version de MySQL en RDS (8.4 es la version LTS)"
  type        = string
  default     = "8.4"
}

variable "db_allocated_storage" {
  description = "Almacenamiento de la base de datos en GB"
  type        = number
  default     = 20
}

# ---------------------------------------------------------------------------
# Base de datos en memoria (Amazon ElastiCache for Valkey)
# ---------------------------------------------------------------------------
variable "cache_node_type" {
  description = "Tipo de nodo de ElastiCache"
  type        = string
  default     = "cache.t4g.micro"
}

variable "cache_engine_version" {
  description = "Version de Valkey en ElastiCache"
  type        = string
  default     = "8.0"
}

# ---------------------------------------------------------------------------
# Instalacion automatica de Joomla (las contrasenas las genera Terraform)
# ---------------------------------------------------------------------------
variable "site_name" {
  description = "Nombre del sitio Joomla"
  type        = string
  default     = "Joomla en AWS - Actividad 6"
}

variable "admin_name" {
  description = "Nombre visible del superusuario de Joomla"
  type        = string
  default     = "Administrador"
}

variable "admin_username" {
  description = "Usuario de ingreso del superusuario (solo letras)"
  type        = string
  default     = "admin"

  validation {
    condition     = can(regex("^[A-Za-z]+$", var.admin_username))
    error_message = "admin_username solo puede tener letras, sin espacios ni numeros."
  }
}

variable "admin_email" {
  description = "Correo del superusuario de Joomla"
  type        = string
  default     = "admin@example.com"
}

# ---------------------------------------------------------------------------
# Observabilidad
# ---------------------------------------------------------------------------
variable "alert_email" {
  description = "Correo que recibe las alarmas. Llega como secreto (TF_VAR_alert_email); vacio = sin correo"
  type        = string
  default     = ""
}

variable "alb_5xx_per_minute_threshold" {
  description = "Errores 5xx por minuto que disparan la alarma del balanceador"
  type        = number
  default     = 10
}

variable "latency_p95_seconds_threshold" {
  description = "Latencia p95 (segundos) que dispara la alarma"
  type        = number
  default     = 2
}

variable "php_fatal_per_minute_threshold" {
  description = "Errores fatales de PHP por minuto que disparan la alarma"
  type        = number
  default     = 5
}

variable "db_max_connections_threshold" {
  description = "Conexiones a MySQL que disparan la alarma (db.t4g.micro admite unas 85)"
  type        = number
  default     = 60
}
