resource "aws_ecr_repository" "images" {
  for_each             = local.service_config
  name                 = "${var.project_name}-${each.key}"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  force_delete = true
  tags = { Project = var.project_name, Service = each.key }
}

resource "aws_sqs_queue" "bookings" {
  name                       = "${var.project_name}-bookings"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 10
  tags = { Project = var.project_name }
}

resource "random_password" "db" {
  count            = var.db_password == "" ? 1 : 0
  length           = 24
  special          = false
  override_special = ""
}

locals {
  database_password = var.db_password != "" ? var.db_password : random_password.db[0].result
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = [for subnet in aws_subnet.private : subnet.id]
  tags       = { Name = "${var.project_name}-db-subnets" }
}

resource "aws_db_instance" "postgres" {
  identifier                 = "${var.project_name}-postgres"
  engine                     = "postgres"
  instance_class             = var.db_instance_class
  allocated_storage          = 20
  max_allocated_storage      = 30
  storage_type               = "gp3"
  storage_encrypted          = true
  db_name                    = var.db_name
  username                   = var.db_username
  password                   = local.database_password
  port                       = 5432
  db_subnet_group_name       = aws_db_subnet_group.postgres.name
  vpc_security_group_ids     = [aws_security_group.database.id]
  publicly_accessible        = false
  multi_az                   = false
  backup_retention_period    = 0
  auto_minor_version_upgrade = true
  apply_immediately          = true
  deletion_protection        = false
  skip_final_snapshot        = true
  tags = { Name = "${var.project_name}-postgres", Project = var.project_name }
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project_name}-redis-subnets"
  subnet_ids = [for subnet in aws_subnet.private : subnet.id]
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.cache.id]
  tags = { Name = "${var.project_name}-redis", Project = var.project_name }
}
