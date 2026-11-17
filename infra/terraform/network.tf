locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  service_config = {
    search = {
      priority     = 10
      paths        = ["/search", "/search/*"]
      min_size     = var.min_capacity
      desired_size = var.desired_capacity
    }
    listing = {
      priority     = 20
      paths        = ["/listings", "/listings/*"]
      min_size     = var.min_capacity
      desired_size = var.desired_capacity
    }
    booking = {
      priority     = 30
      paths        = ["/bookings", "/bookings/*"]
      min_size     = var.min_capacity
      desired_size = var.desired_capacity
    }
    monolith = {
      priority     = 40
      paths        = ["/monolith", "/monolith/*"]
      min_size     = 0
      desired_size = 0
    }
  }

  app_environment = {
    APP_ENV              = "aws"
    AWS_REGION           = var.aws_region
    DB_HOST              = aws_db_instance.postgres.address
    DB_PORT              = tostring(aws_db_instance.postgres.port)
    DB_NAME              = var.db_name
    DB_USER              = var.db_username
    DB_PASSWORD          = local.database_password
    DB_POOL_MIN          = "1"
    DB_POOL_MAX          = tostring(var.db_pool_max)
    CACHE_HOST           = var.create_redis ? aws_elasticache_cluster.redis[0].cache_nodes[0].address : "localhost"
    CACHE_PORT           = var.create_redis ? tostring(aws_elasticache_cluster.redis[0].cache_nodes[0].port) : "6379"
    CACHE_ENABLED        = tostring(var.create_redis && var.cache_enabled)
    BOOKING_ASYNC        = tostring(var.booking_async)
    SQS_QUEUE_URL        = aws_sqs_queue.bookings.url
    SQS_QUEUE_NAME       = aws_sqs_queue.bookings.name
    LISTING_DATASET_SIZE = tostring(var.dataset_size)
    SEARCH_CPU_WORK_MS   = tostring(var.search_cpu_work_ms)
    SEARCH_MAX_WORK_MS   = "500"
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "public" {
  for_each                = { for index, az in local.azs : az => index }
  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.value)
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-public-${each.value + 1}" }
}

resource "aws_subnet" "private" {
  for_each          = { for index, az in local.azs : az => index }
  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, each.value + 10)
  tags              = { Name = "${var.project_name}-private-${each.value + 1}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Public HTTP ingress to the Application Load Balancer only."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-alb-sg" }
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Application instances accept traffic only from the ALB."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App HTTP from ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-app-sg" }
}

resource "aws_security_group" "database" {
  name        = "${var.project_name}-db-sg"
  description = "PostgreSQL accessible only from app instances."
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-db-sg" }
}

resource "aws_security_group" "cache" {
  name        = "${var.project_name}-cache-sg"
  description = "Redis accessible only from app instances."
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-cache-sg" }
}
