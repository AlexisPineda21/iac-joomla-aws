terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Etiquetas que se aplican a todos los recursos
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Pipeline  = "github-actions"
      Course    = "Introduccion a Modelos de Informatica en la Nube - ITM"
      Activity  = "Actividad 6 - IaC CI-CD Observabilidad"
    }
  }
}
