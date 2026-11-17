variable "aws_region" {
  description = "AWS region for the proof of concept."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  type    = string
  default = "airbnb-soa-poc"
}

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "instance_type" {
  description = "EC2 type for app instances. Use t3 (not t2): t2 throttles to baseline CPU once credits run out, which corrupts load-test results."
  type        = string
  default     = "t3.micro"
}

variable "cpu_credits" {
  description = "CPU credit mode for T-family instances: unlimited (no throttling, tiny surplus charge possible) or standard (credit-safe, throttles when credits run out)."
  type        = string
  default     = "unlimited"
  validation {
    condition     = contains(["unlimited", "standard"], var.cpu_credits)
    error_message = "cpu_credits must be unlimited or standard."
  }
}

variable "cpu_bound_workers" {
  description = "Uvicorn worker processes for the CPU-bound search and monolith services. Python runs one request at a time per process (GIL), so this should equal the instance vCPU count (t3.micro = 2)."
  type        = number
  default     = 2
}

variable "min_capacity" {
  type    = number
  default = 1
}

variable "desired_capacity" {
  type    = number
  default = 1
}

variable "max_capacity" {
  type    = number
  default = 8
}

variable "scaling_mode" {
  description = "none (manual capacity), target (50% CPU target tracking), step, or scheduled (pre-warm + target tracking)."
  type        = string
  default     = "target"
  validation {
    condition     = contains(["none", "target", "step", "scheduled"], var.scaling_mode)
    error_message = "scaling_mode must be none, target, step, or scheduled."
  }
}

variable "cpu_target_percent" {
  type    = number
  default = 50
}

variable "instance_warmup_seconds" {
  description = "Set near the observed EC2 boot + application-ready time."
  type        = number
  default     = 180
}

variable "prewarm_capacity" {
  description = "Desired/minimum instance count for the scheduled holiday warm-up."
  type        = number
  default     = 3
}

variable "prewarm_cron" {
  description = "UTC cron expression for the scheduled pre-warm action (AWS cron format). Update for the experiment window."
  type        = string
  default     = "0 12 * * *"
}

variable "restore_cron" {
  description = "UTC cron expression for restoring the normal minimum after pre-warm."
  type        = string
  default     = "30 12 * * *"
}

variable "db_name" {
  type    = string
  default = "airbnbpoc"
}

variable "db_username" {
  type    = string
  default = "airbnb"
}

variable "db_password" {
  description = "Optional override. Leave blank to generate a random password stored in Terraform state."
  type        = string
  sensitive   = true
  default     = ""
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "redis_node_type" {
  type    = string
  default = "cache.t3.micro"
}

variable "dataset_size" {
  type    = number
  default = 50000
}

variable "search_cpu_work_ms" {
  description = "CPU work per search request. Calibrate in Week 3; keep constant across comparison runs."
  type        = number
  default     = 80
}

variable "db_pool_max" {
  description = "Maximum PostgreSQL connections per application process/instance. Keep low for the small RDS class."
  type        = number
  default     = 3
}

variable "create_loadgen_instance" {
  description = "Create an optional same-region EC2 instance with k6 installed; this instance incurs extra cost while running."
  type        = bool
  default     = false
}

variable "create_budget" {
  description = "Create an AWS Budget. Requires billing/budgets permissions."
  type        = bool
  default     = false
}

variable "budget_limit_usd" {
  type    = number
  default = 25
}

variable "budget_alert_email" {
  description = "Email address for budget alerts; required when create_budget=true."
  type        = string
  default     = ""
}

variable "cache_enabled" {
  description = "Toggle Redis cache-aside for E4. Changing it updates the launch template and refreshes ASG instances."
  type        = bool
  default     = true
}

variable "booking_async" {
  description = "Use SQS + worker when true; write booking completion directly to PostgreSQL when false (E5 comparison)."
  type        = bool
  default     = true
}


variable "create_redis" {
  description = "Create the ElastiCache Redis node. Redis is only a read cache (cache-aside); set false to save cost. All shared state lives in Postgres."
  type        = bool
  default     = true
}
