resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "sqs" {
  name = "${var.project_name}-sqs-access"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
      Resource = aws_sqs_queue.bookings.arn
    }]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_lb" "app" {
  name               = substr("${var.project_name}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]
  tags = { Name = "${var.project_name}-alb", Project = var.project_name }
}

resource "aws_lb_target_group" "service" {
  for_each    = local.service_config
  name        = substr("${var.project_name}-${each.key}-tg", 0, 32)
  port        = 8000
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 20
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  tags = { Name = "${var.project_name}-${each.key}-tg", Project = var.project_name }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"route_not_found\"}"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "service_paths" {
  for_each     = local.service_config
  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service[each.key].arn
  }
  condition {
    path_pattern { values = each.value.paths }
  }
}

resource "aws_launch_template" "app" {
  for_each      = local.service_config
  name_prefix   = "${var.project_name}-${each.key}-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type
  update_default_version = true

  iam_instance_profile { name = aws_iam_instance_profile.ec2.name }
  vpc_security_group_ids = [aws_security_group.app.id]
  monitoring { enabled = true }

  # T-family instances. "unlimited" never throttles (small surplus-credit charge possible); "standard" is credit-safe but throttles once credits run out - keep runs time-boxed.
  dynamic "credit_specification" {
    for_each = startswith(var.instance_type, "t") ? [1] : []
    content {
      cpu_credits = var.cpu_credits
    }
  }

  user_data = base64encode(templatefile("${path.module}/templates/app-user-data.sh.tftpl", {
    aws_region = var.aws_region
    ecr_registry = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
    image_uri = "${aws_ecr_repository.images[each.key].repository_url}:latest"
    env_file = join("\n", [for key, value in merge(local.app_environment, {
      SERVICE_NAME    = each.key
      WEB_CONCURRENCY = contains(["search", "monolith"], each.key) ? tostring(var.cpu_bound_workers) : "1"
    }) : "${key}=${value}"])
    run_worker = contains(["booking", "monolith"], each.key)
  }))

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "${var.project_name}-${each.key}", Project = var.project_name, Service = each.key }
  }
  tag_specifications {
    resource_type = "volume"
    tags = { Project = var.project_name, Service = each.key }
  }
}

resource "aws_autoscaling_group" "service" {
  for_each                  = local.service_config
  name                      = "${var.project_name}-${each.key}-asg"
  min_size                  = each.value.min_size
  desired_capacity          = each.value.desired_size
  max_size                  = var.max_capacity
  vpc_zone_identifier       = [for subnet in aws_subnet.public : subnet.id]
  target_group_arns         = [aws_lb_target_group.service[each.key].arn]
  health_check_type         = "ELB"
  health_check_grace_period = 240
  default_instance_warmup   = var.instance_warmup_seconds
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      max_healthy_percentage = 200
      instance_warmup        = var.instance_warmup_seconds
    }
    triggers = ["launch_template"]
  }
  metrics_granularity       = "1Minute"
  enabled_metrics = [
    "GroupMinSize", "GroupMaxSize", "GroupDesiredCapacity",
    "GroupInServiceInstances", "GroupPendingInstances"
  ]

  launch_template {
    id      = aws_launch_template.app[each.key].id
    version = aws_launch_template.app[each.key].latest_version
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${each.key}"
    propagate_at_launch = true
  }
  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "target_tracking" {
  for_each = contains(["target", "scheduled"], var.scaling_mode) ? local.service_config : {}
  name                   = "${var.project_name}-${each.key}-cpu-target-${var.cpu_target_percent}"
  autoscaling_group_name = aws_autoscaling_group.service[each.key].name
  policy_type            = "TargetTrackingScaling"
  estimated_instance_warmup = var.instance_warmup_seconds
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target_percent
  }
}

resource "aws_cloudwatch_metric_alarm" "step_high" {
  for_each            = var.scaling_mode == "step" ? local.service_config : {}
  alarm_name          = "${var.project_name}-${each.key}-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = var.cpu_target_percent
  treat_missing_data  = "notBreaching"
  dimensions = { AutoScalingGroupName = aws_autoscaling_group.service[each.key].name }
  alarm_actions = [aws_autoscaling_policy.step_out[each.key].arn]
}

resource "aws_autoscaling_policy" "step_out" {
  for_each               = var.scaling_mode == "step" ? local.service_config : {}
  name                   = "${var.project_name}-${each.key}-step-out"
  autoscaling_group_name = aws_autoscaling_group.service[each.key].name
  policy_type            = "StepScaling"
  adjustment_type        = "ChangeInCapacity"
  metric_aggregation_type      = "Average"
  step_adjustment {
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 20
    scaling_adjustment          = 1
  }
  step_adjustment {
    metric_interval_lower_bound = 20
    scaling_adjustment          = 2
  }
}

resource "aws_cloudwatch_metric_alarm" "step_low" {
  for_each            = var.scaling_mode == "step" ? local.service_config : {}
  alarm_name          = "${var.project_name}-${each.key}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 25
  treat_missing_data  = "notBreaching"
  dimensions = { AutoScalingGroupName = aws_autoscaling_group.service[each.key].name }
  alarm_actions = [aws_autoscaling_policy.step_in[each.key].arn]
}

resource "aws_autoscaling_policy" "step_in" {
  for_each               = var.scaling_mode == "step" ? local.service_config : {}
  name                   = "${var.project_name}-${each.key}-step-in"
  autoscaling_group_name = aws_autoscaling_group.service[each.key].name
  policy_type            = "StepScaling"
  adjustment_type        = "ChangeInCapacity"
  metric_aggregation_type      = "Average"
  step_adjustment {
    metric_interval_upper_bound = 0
    scaling_adjustment          = -1
  }
}

resource "aws_autoscaling_schedule" "prewarm" {
  for_each               = var.scaling_mode == "scheduled" ? { for name, cfg in local.service_config : name => cfg if name != "monolith" } : {}
  scheduled_action_name  = "${var.project_name}-${each.key}-prewarm"
  autoscaling_group_name = aws_autoscaling_group.service[each.key].name
  recurrence             = var.prewarm_cron
  min_size               = var.prewarm_capacity
  desired_capacity       = var.prewarm_capacity
  max_size               = var.max_capacity
}

resource "aws_autoscaling_schedule" "restore" {
  for_each               = var.scaling_mode == "scheduled" ? { for name, cfg in local.service_config : name => cfg if name != "monolith" } : {}
  scheduled_action_name  = "${var.project_name}-${each.key}-restore"
  autoscaling_group_name = aws_autoscaling_group.service[each.key].name
  recurrence             = var.restore_cron
  min_size               = each.value.min_size
  desired_capacity       = each.value.desired_size
  max_size               = var.max_capacity
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"
  dashboard_body = jsonencode({
    widgets = concat(
      [{
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title = "ALB requests and target response time"
          view = "timeSeries", stacked = false, region = var.aws_region, period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.app.arn_suffix, { stat = "Sum", label = "Requests" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.app.arn_suffix, "TargetGroup", aws_lb_target_group.service["search"].arn_suffix, { stat = "Average", label = "Search target latency" }]
          ]
        }
      }],
      [for index, service in keys(local.service_config) : {
        type = "metric", x = (index % 2) * 12, y = 6 + floor(index / 2) * 6, width = 12, height = 6,
        properties = {
          title = "${service} ASG CPU and in-service instances"
          view = "timeSeries", stacked = false, region = var.aws_region, period = 60
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.service[service].name, { stat = "Average", label = "CPU %" }],
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", aws_autoscaling_group.service[service].name, { stat = "Average", yAxis = "right", label = "In-service instances" }]
          ]
        }
      }]
    )
  })
}

resource "aws_instance" "load_generator" {
  count                       = var.create_loadgen_instance ? 1 : 0
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.small"
  subnet_id                   = values(aws_subnet.public)[0].id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true
  user_data = <<-USERDATA
    #!/bin/bash
    set -euxo pipefail
    dnf install -y curl git
    dnf install -y https://dl.k6.io/rpm/repo.rpm
    dnf install -y k6
    echo "k6 load generator ready" > /home/ec2-user/LOADGEN_READY
    chown ec2-user:ec2-user /home/ec2-user/LOADGEN_READY
  USERDATA
  tags = { Name = "${var.project_name}-k6-runner", Project = var.project_name }
}

resource "aws_budgets_budget" "monthly" {
  count             = var.create_budget ? 1 : 0
  name              = "${var.project_name}-monthly-budget"
  budget_type       = "COST"
  limit_amount      = tostring(var.budget_limit_usd)
  limit_unit        = "USD"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 75
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 90
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
