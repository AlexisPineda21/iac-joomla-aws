output "state_bucket" {
  description = "Bucket S3 con el estado remoto de infra/"
  value       = aws_s3_bucket.tfstate.bucket
}

output "ecr_repository_url" {
  description = "Repositorio ECR de la imagen de Joomla"
  value       = aws_ecr_repository.app.repository_url
}

output "role_arns" {
  description = "Roles IAM que asumen los pipelines por OIDC"
  value = {
    iac_plan  = aws_iam_role.iac_plan.arn
    iac_apply = aws_iam_role.iac_apply.arn
    app       = aws_iam_role.app.arn
  }
}

output "iac_repo_url" {
  description = "Repositorio de infraestructura"
  value       = github_repository.iac.html_url
}

output "app_repo_url" {
  description = "Repositorio de la aplicacion"
  value       = github_repository.app.html_url
}

output "git_remotes" {
  description = "Comandos para conectar las carpetas locales con los repositorios"
  value = {
    iac = "git remote add origin ${github_repository.iac.http_clone_url}"
    app = "git remote add origin ${github_repository.app.http_clone_url}"
  }
}
