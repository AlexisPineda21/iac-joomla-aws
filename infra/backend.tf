# Estado remoto en S3 (bucket creado por ../bootstrap) con bloqueo nativo: Terraform
# crea un archivo .tflock junto al estado mientras hay una operacion en curso.
# El bucket y la region llegan en el init del pipeline:
#   terraform init -backend-config="bucket=<TF_STATE_BUCKET>" -backend-config="region=<AWS_REGION>"
terraform {
  backend "s3" {
    key          = "joomla-ecs/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
