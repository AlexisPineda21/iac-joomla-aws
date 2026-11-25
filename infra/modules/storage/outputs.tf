output "file_system_id" {
  value = aws_efs_file_system.joomla.id
}

output "access_point_id" {
  value = aws_efs_access_point.joomla.id
}

output "mount_target_ids" {
  value = aws_efs_mount_target.private[*].id
}
