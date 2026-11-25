# ---------------------------------------------------------------------------
# Almacenamiento persistente: Amazon EFS (NFS gestionado)
# El codigo de Joomla viaja en la imagen y se renueva con cada despliegue. En EFS
# solo queda lo que cambia en ejecucion: configuration.php y la carpeta images/
# (archivos subidos desde el panel). Todas las tareas montan el mismo EFS.
# ---------------------------------------------------------------------------

resource "aws_efs_file_system" "joomla" {
  creation_token   = "${var.project_name}-efs"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = { Name = "${var.project_name}-efs" }
}

# Un punto de montaje por subred privada (una por zona de disponibilidad)
resource "aws_efs_mount_target" "private" {
  count = length(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.joomla.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [var.security_group_id]
}

# Punto de acceso: carpeta /joomla; todo se lee y escribe como www-data (UID/GID 33)
resource "aws_efs_access_point" "joomla" {
  file_system_id = aws_efs_file_system.joomla.id

  posix_user {
    uid = 33
    gid = 33
  }

  root_directory {
    path = "/joomla"

    creation_info {
      owner_uid   = 33
      owner_gid   = 33
      permissions = "0755"
    }
  }

  tags = { Name = "${var.project_name}-efs-ap" }
}
