# ---------------------------------------------------------------------------
# Servicio contenerizado gestionado: Amazon ECS con AWS Fargate
#   - Cluster de ECS
#   - Definicion de tarea: imagen del fork joomla-app (ECR) con EFS montado
#   - Servicio: rolling update sin caida y rollback automatico (circuit breaker)
#   - Application Load Balancer: punto de entrada publico por HTTP
# ---------------------------------------------------------------------------

# Logs del contenedor (Apache, PHP y el script de arranque) en CloudWatch
resource "aws_cloudwatch_log_group" "joomla" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = var.log_retention_days

  tags = { Name = "${var.project_name}-logs" }
}

# Contrasenas en SSM Parameter Store (cifradas): no quedan en texto plano en la tarea
resource "aws_ssm_parameter" "db_password" {
  name        = "/${var.project_name}/db_password"
  description = "Contrasena de la base de datos de Joomla"
  type        = "SecureString"
  value       = var.db_password
}

resource "aws_ssm_parameter" "admin_password" {
  name        = "/${var.project_name}/admin_password"
  description = "Contrasena del superusuario de Joomla"
  type        = "SecureString"
  value       = var.admin_password
}

# URL publica del sitio: la lee el pipeline de joomla-app para el smoke test
resource "aws_ssm_parameter" "app_url" {
  name        = "/${var.project_name}/app/url"
  description = "URL publica de Joomla (ALB)"
  type        = "String"
  value       = "http://${aws_lb.joomla.dns_name}"
}

# ---------------------------------------------------------------------------
# IAM: rol de ejecucion (lo usa ECS para descargar la imagen de ECR, escribir logs y
# leer secretos) y rol de la tarea (lo usa el contenedor; permite ECS Exec)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.project_name}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secrets" {
  name = "read-joomla-secrets"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameters"]
      Resource = [aws_ssm_parameter.db_password.arn, aws_ssm_parameter.admin_password.arn]
    }]
  })
}

resource "aws_iam_role" "task" {
  name               = "${var.project_name}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "task_exec" {
  name = "ecs-exec"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ]
      Resource = "*"
    }]
  })
}

# ---------------------------------------------------------------------------
# Balanceador de carga (ALB)
# ---------------------------------------------------------------------------
resource "aws_lb" "joomla" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids
  idle_timeout       = 120

  drop_invalid_header_fields = true

  tags = { Name = "${var.project_name}-alb" }
}

resource "aws_lb_target_group" "joomla" {
  name                 = "${var.project_name}-tg"
  port                 = 80
  protocol             = "HTTP"
  target_type          = "ip" # Fargate registra la IP de cada tarea
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  # /health.php responde 200 solo si el contenedor llega a MySQL y a Valkey
  health_check {
    path                = "/health.php"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.project_name}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.joomla.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.joomla.arn
  }
}

# ---------------------------------------------------------------------------
# ECS: cluster, definicion de tarea y servicio
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled" # Las metricas basicas de ECS (CPU y memoria) son gratuitas
  }
}

resource "aws_ecs_task_definition" "joomla" {
  family                   = "${var.project_name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  volume {
    name = "joomla-data"

    efs_volume_configuration {
      file_system_id     = var.efs_file_system_id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = var.efs_access_point_id
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([{
    name      = "joomla"
    image     = var.image
    essential = true

    # Sin entryPoint ni command: la imagen arranca con start-joomla (ver joomla-app)
    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]

    environment = [
      { name = "JOOMLA_DB_HOST", value = "${var.db_host}:${var.db_port}" },
      { name = "JOOMLA_DB_NAME", value = var.db_name },
      { name = "JOOMLA_DB_USER", value = var.db_username },
      { name = "JOOMLA_DB_TYPE", value = "mysqli" },
      { name = "JOOMLA_SITE_NAME", value = var.site_name },
      { name = "JOOMLA_ADMIN_USER", value = var.admin_name },
      { name = "JOOMLA_ADMIN_USERNAME", value = var.admin_username },
      { name = "JOOMLA_ADMIN_EMAIL", value = var.admin_email },
      { name = "JOOMLA_REDIS_HOST", value = var.cache_host },
      { name = "JOOMLA_REDIS_PORT", value = tostring(var.cache_port) },
      { name = "JOOMLA_DATA_DIR", value = "/mnt/joomla-data" },
      { name = "FAULT_INJECTION", value = var.fault_injection_enabled ? "enabled" : "disabled" }
    ]

    secrets = [
      { name = "JOOMLA_DB_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn },
      { name = "JOOMLA_ADMIN_PASSWORD", valueFrom = aws_ssm_parameter.admin_password.arn }
    ]

    mountPoints = [{
      sourceVolume  = "joomla-data"
      containerPath = "/mnt/joomla-data"
      readOnly      = false
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.joomla.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "joomla"
      }
    }

    linuxParameters = {
      initProcessEnabled = true # Recomendado para ECS Exec
    }
  }])

  tags = { Name = "${var.project_name}-task" }
}

resource "aws_ecs_service" "joomla" {
  name             = "${var.project_name}-service"
  cluster          = aws_ecs_cluster.main.id
  task_definition  = aws_ecs_task_definition.joomla.arn
  desired_count    = var.desired_count
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  enable_execute_command  = true
  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  # La primera tarea instala Joomla (1 a 3 minutos): el balanceador no la evalua antes
  health_check_grace_period_seconds = 600

  # Rolling update sin caida: la tarea nueva arranca y queda sana antes de retirar la
  # vieja. Es posible porque el codigo esta en la imagen y no en EFS.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # Si las tareas nuevas no logran quedar sanas, ECS vuelve a la version anterior
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [var.app_security_group_id]
    assign_public_ip = true # Para llegar a ECR, CloudWatch y SSM sin NAT Gateway
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.joomla.arn
    container_name   = "joomla"
    container_port   = 80
  }

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.execution,
    aws_iam_role_policy.execution_secrets
  ]

  tags = { Name = "${var.project_name}-service" }
}
