# Terraform stack

Run from this directory. Copy `terraform.tfvars.example` to `terraform.tfvars` and review every value before applying.

## Safe staged deployment

1. `terraform init`
2. `terraform apply -target=aws_ecr_repository.images -var-file=terraform.tfvars`
3. From the project root, run `./scripts/build-push.sh`.
4. `terraform plan -var-file=terraform.tfvars`
5. `terraform apply -var-file=terraform.tfvars`

The second apply creates the VPC, ALB, four ASGs, RDS, Redis and SQS. App instances pull their images from ECR during user-data bootstrap. Wait for ALB target health checks and listing database seeding before load tests.

## Variables that change between experiments

- `scaling_mode`: `none`, `target`, `step`, `scheduled`
- `cache_enabled`: `true` / `false` for E4
- `booking_async`: `true` / `false` for E5
- `search_cpu_work_ms`: calibrate early, then keep fixed
- `prewarm_cron`, `restore_cron`, `prewarm_capacity`: scheduled warm-up window (UTC)

After changing a launch-template environment value, the Auto Scaling Group instance refresh replaces instances. Wait for target health before testing.

## Notes

- No NAT Gateway is created. EC2 app instances use public subnets and outbound internet; ingress on port 8000 is allowed only from the ALB security group. RDS and Redis are private.
- `db_password` is generated if omitted and is stored in Terraform state/user data. Treat state as sensitive. This is not a production secret-management pattern.
- `create_loadgen_instance` and `create_budget` default to false. Enable them deliberately.
- The project assumes two available AZs in the selected region.
- Check your AWS quotas and the price calculator before creating anything.
