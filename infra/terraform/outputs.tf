output "alb_dns_name" {
  value       = aws_lb.app.dns_name
  description = "Public HTTP DNS name for the API."
}

output "alb_base_url" {
  value       = "http://${aws_lb.app.dns_name}"
  description = "Use as BASE_URL for k6."
}

output "autoscaling_group_names" {
  value = { for name, group in aws_autoscaling_group.service : name => group.name }
}

output "target_group_arns" {
  value = { for name, group in aws_lb_target_group.service : name => group.arn }
}

output "ecr_repository_urls" {
  value = { for name, repo in aws_ecr_repository.images : name => repo.repository_url }
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.address
}

output "redis_endpoint" {
  value = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "sqs_queue_url" {
  value = aws_sqs_queue.bookings.url
}

output "cloudwatch_dashboard_name" {
  value = aws_cloudwatch_dashboard.main.dashboard_name
}

output "database_password" {
  value     = local.database_password
  sensitive = true
}

output "load_generator_instance_id" {
  value       = try(aws_instance.load_generator[0].id, null)
  description = "Present only when create_loadgen_instance=true."
}
