variable "aws_region" {
  description = "Region de AWS (la misma de infra/)"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo de los recursos. Debe coincidir con project_name de infra/env/prod.tfvars"
  type        = string
  default     = "joomla-ecs"
}

variable "github_owner" {
  description = "Usuario de GitHub donde se crean los dos repositorios"
  type        = string
}

variable "iac_repo_name" {
  description = "Repositorio de la infraestructura (este codigo)"
  type        = string
  default     = "iac-joomla-aws"
}

variable "app_repo_name" {
  description = "Repositorio de la aplicacion (fork de Joomla)"
  type        = string
  default     = "joomla-app"
}

variable "ecr_repository_name" {
  description = "Repositorio de ECR para la imagen de Joomla"
  type        = string
  default     = "joomla-app"
}

variable "terraform_version" {
  description = "Version de Terraform que usan los pipelines"
  type        = string
  default     = "1.17.2"
}

variable "alert_email" {
  description = "Correo para el presupuesto y las alarmas de CloudWatch. Vacio = sin notificaciones por correo"
  type        = string
  default     = ""

  validation {
    condition     = var.alert_email == "" || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email debe ser un correo valido o quedar vacio."
  }
}

variable "monthly_budget_usd" {
  description = "Presupuesto mensual de la cuenta en USD (avisa al 80 % real y al 100 % proyectado)"
  type        = number
  default     = 20
}

variable "create_github_oidc_provider" {
  description = "false si la cuenta ya tiene el proveedor OIDC de GitHub (token.actions.githubusercontent.com)"
  type        = bool
  default     = true
}
