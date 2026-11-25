terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Stack     = "bootstrap"
      Course    = "Introduccion a Modelos de Informatica en la Nube - ITM"
      Activity  = "Actividad 6 - IaC CI-CD Observabilidad"
    }
  }
}

# Usa el token de GitHub CLI: export GITHUB_TOKEN=$(gh auth token)
provider "github" {
  owner = var.github_owner
}
