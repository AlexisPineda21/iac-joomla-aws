plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.50.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Valkey usa a proposito su grupo de parametros por defecto (default.valkey8)
rule "aws_elasticache_replication_group_default_parameter_group" {
  enabled = false
}
