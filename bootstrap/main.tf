# ---------------------------------------------------------------------------
# Bootstrap del CI/CD. Se ejecuta UNA vez desde el computador (estado local) y crea
# lo que los pipelines necesitan antes de poder correr:
#   AWS:    bucket S3 del estado remoto, repositorio ECR, proveedor OIDC de GitHub,
#           roles IAM de los pipelines y presupuesto de la cuenta.
#   GitHub: los dos repositorios, el environment "production" (con aprobacion en el
#           de infraestructura) y las variables/secretos de GitHub Actions.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# Usuario autenticado en GitHub: da el login exacto (mayusculas incluidas) y el id
# que se usa como aprobador del environment.
data "github_user" "current" {
  username = ""
}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  github_login  = data.github_user.current.login
  state_bucket  = "tfstate-${var.project_name}-${local.account_id}"
  cluster_name  = "${var.project_name}-cluster"
  service_name  = "${var.project_name}-service"
  url_parameter = "/${var.project_name}/app/url"
}

# ---------------------------------------------------------------------------
# Estado remoto de infra/ (S3 con bloqueo nativo por archivo .tflock)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = local.state_bucket

  # Curso: permite borrar el bucket con "terraform destroy" al terminar.
  # En un proyecto real va en false.
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Conserva las 20 versiones anteriores mas recientes del estado
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "keep-last-20-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days           = 1
      newer_noncurrent_versions = 20
    }
  }

  depends_on = [aws_s3_bucket_versioning.tfstate]
}

# Solo conexiones cifradas (HTTPS) al bucket
resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

# ---------------------------------------------------------------------------
# Registro de imagenes (ECR) para el fork de Joomla
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "app" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE" # "latest" se mueve en cada despliegue y en los rollback
  force_delete         = true      # Curso: permite borrar el repositorio aunque tenga imagenes

  image_scanning_configuration {
    scan_on_push = true # Escaneo de vulnerabilidades de cada imagen
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Borrar imagenes sin tag despues de 14 dias"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Conservar las 20 imagenes mas recientes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 20
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# OIDC: GitHub Actions obtiene credenciales temporales de AWS sin llaves guardadas
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  # "sub" del token de GitHub. Los repositorios creados desde el 15 jul 2026 usan el
  # formato con IDs inmutables (repo:<usuario>@<id>/<repo>@<id>:<contexto>); los mas
  # antiguos, el clasico (repo:<usuario>/<repo>:<contexto>). Se aceptan ambos.
  # Cada rol solo acepta tokens de su repositorio y de su contexto.
  github_user_id = data.github_user.current.id

  iac_repo_subjects = [
    "repo:${local.github_login}/${var.iac_repo_name}",
    "repo:${local.github_login}@${local.github_user_id}/${var.iac_repo_name}@${github_repository.iac.repo_id}",
  ]
  app_repo_subjects = [
    "repo:${local.github_login}/${var.app_repo_name}",
    "repo:${local.github_login}@${local.github_user_id}/${var.app_repo_name}@${github_repository.app.repo_id}",
  ]

  github_subjects = {
    iac_plan = flatten([
      for repo in local.iac_repo_subjects : ["${repo}:pull_request", "${repo}:ref:refs/heads/main"]
    ])
    iac_apply = [for repo in local.iac_repo_subjects : "${repo}:environment:production"]
    app       = [for repo in local.app_repo_subjects : "${repo}:environment:production"]
  }
}

data "aws_iam_policy_document" "github_trust" {
  for_each = local.github_subjects

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

# Plan (en los PR y antes de cada apply): solo lectura, no puede cambiar nada en la cuenta
resource "aws_iam_role" "iac_plan" {
  name                 = "${var.project_name}-github-iac-plan"
  description          = "GitHub Actions: terraform plan en PR de ${var.iac_repo_name}"
  assume_role_policy   = data.aws_iam_policy_document.github_trust["iac_plan"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "iac_plan" {
  role       = aws_iam_role.iac_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Apply y destroy: solo desde el environment "production", que exige aprobacion
resource "aws_iam_role" "iac_apply" {
  name                 = "${var.project_name}-github-iac-apply"
  description          = "GitHub Actions: terraform apply/destroy de ${var.iac_repo_name} (environment production)"
  assume_role_policy   = data.aws_iam_policy_document.github_trust["iac_apply"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "iac_apply" {
  role       = aws_iam_role.iac_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Despliegue de la aplicacion: solo publicar en su repositorio ECR y reiniciar su servicio
resource "aws_iam_role" "app" {
  name                 = "${var.project_name}-github-app-deploy"
  description          = "GitHub Actions: build, push y despliegue de ${var.app_repo_name}"
  assume_role_policy   = data.aws_iam_policy_document.github_trust["app"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "app" {
  name = "ecr-push-ecs-deploy"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPushAndRetag"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Sid      = "EcsDeploy"
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = "arn:aws:ecs:${var.aws_region}:${local.account_id}:service/${local.cluster_name}/${local.service_name}"
      },
      {
        Sid      = "ReadAppParameters"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:${local.account_id}:parameter/${var.project_name}/app/*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Presupuesto de la cuenta (solo si hay correo)
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  count = var.alert_email == "" ? 0 : 1

  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

# ---------------------------------------------------------------------------
# GitHub: repositorios, environments, variables y secretos de Actions
# Publicos: GitHub Free solo permite aprobadores en environments de repos publicos.
# ---------------------------------------------------------------------------
resource "github_repository" "iac" {
  name        = var.iac_repo_name
  description = "IaC (Terraform) de Joomla en AWS: ECS Fargate, RDS MySQL, ElastiCache Valkey, EFS y CloudWatch, con CI/CD en GitHub Actions"
  visibility  = "public"

  has_issues             = true
  delete_branch_on_merge = true
  archive_on_destroy     = true # Al destruir el bootstrap el repositorio se archiva, no se borra
}

resource "github_repository" "app" {
  name        = var.app_repo_name
  description = "Fork de Joomla 5.4.10 con su imagen Docker y CI/CD hacia Amazon ECS"
  visibility  = "public"

  has_issues             = true
  delete_branch_on_merge = true
  archive_on_destroy     = true
}

# Infraestructura: cada apply o destroy espera la aprobacion del usuario, y solo
# se puede desplegar desde main
resource "github_repository_environment" "iac_production" {
  repository          = github_repository.iac.name
  environment         = "production"
  prevent_self_review = false # El mismo usuario hace el push y aprueba (equipo pequeno)

  reviewers {
    users = [tonumber(data.github_user.current.id)]
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "iac_main" {
  repository     = github_repository.iac.name
  environment    = github_repository_environment.iac_production.environment
  branch_pattern = "main"
}

# Aplicacion: despliegue continuo (sin aprobacion), solo desde main
resource "github_repository_environment" "app_production" {
  repository  = github_repository.app.name
  environment = "production"

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "app_main" {
  repository     = github_repository.app.name
  environment    = github_repository_environment.app_production.environment
  branch_pattern = "main"
}

locals {
  iac_variables = {
    AWS_REGION         = var.aws_region
    TF_VERSION         = var.terraform_version
    TF_STATE_BUCKET    = aws_s3_bucket.tfstate.bucket
    AWS_ROLE_PLAN_ARN  = aws_iam_role.iac_plan.arn
    AWS_ROLE_APPLY_ARN = aws_iam_role.iac_apply.arn
  }

  app_variables = {
    AWS_REGION        = var.aws_region
    AWS_ROLE_ARN      = aws_iam_role.app.arn
    ECR_REPOSITORY    = aws_ecr_repository.app.name
    ECS_CLUSTER       = local.cluster_name
    ECS_SERVICE       = local.service_name
    APP_URL_PARAMETER = local.url_parameter
  }
}

resource "github_actions_variable" "iac" {
  for_each = local.iac_variables

  repository    = github_repository.iac.name
  variable_name = each.key
  value         = each.value
}

resource "github_actions_variable" "app" {
  for_each = local.app_variables

  repository    = github_repository.app.name
  variable_name = each.key
  value         = each.value
}

# El correo no va en el repositorio publico: llega al pipeline como secreto
resource "github_actions_secret" "alert_email" {
  count = var.alert_email == "" ? 0 : 1

  repository  = github_repository.iac.name
  secret_name = "ALERT_EMAIL"
  value       = var.alert_email
}
