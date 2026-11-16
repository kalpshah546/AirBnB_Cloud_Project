# AWS deployment plan for a $100 Free Plan credit balance

Target region: `ap-south-1` (Mumbai)

## What the Free Plan allows

AWS's current Free Plan service list includes the services used in this PoC: EC2, EC2 Auto Scaling, ECR, ElastiCache, RDS, SQS, VPC, Elastic Load Balancing, CloudWatch, and AWS Budgets. These are **available services**, not promises that unlimited usage is free. Eligible usage consumes your credits. The account's own Free Plan controls access when credits or plan time run out. Check the Billing console's Cost and Usage widget before deploying.

Official references:
- https://aws.amazon.com/free/
- https://aws.amazon.com/free/free-tier-faqs/
- https://docs.aws.amazon.com/accounts/latest/reference/supported-services-sign-up-new.html

## Cost-safe defaults

Use `infra/terraform/terraform.tfvars.credit-safe.example` as the starting point.

- Three service ASGs start at one `t3.micro` each.
- Each ASG has a normal maximum of two instances.
- The monolith ASG starts at zero and is enabled only during E3.
- The separate k6 EC2 load generator is disabled by default.
- There is no NAT Gateway. Application instances are in public subnets with inbound traffic restricted to the ALB security group; databases/cache remain private.
- PostgreSQL, Redis, and the ALB are still metered resources and should exist only for the planned experiment window.
- E1 temporarily changes only the search ASG to 1, 2, 4, and 8 instances. The runner now restores all service ASGs to a maximum of two afterwards. Confirm your vCPU quota before attempting the 8-instance point.

## Before any apply

1. In Billing and Cost Management, confirm remaining credit, expiration date, and current month's service usage.
2. Confirm the account is still on the Free Plan and `ap-south-1` is the intended project region.
3. Set a monthly AWS Budget alert (example: USD 35) and email notification. A budget is an alert, **not** a hard usage cap and does not automatically stop resources.
4. Check EC2 On-Demand Standard instance vCPU quota. For E1, the search fleet can temporarily reach eight `t3.micro` instances; the load generator adds more quota usage if it is an EC2 instance.
5. Review the Terraform plan. Do not enable the load generator or increase ASG max values until needed.

## Recommended deployment sequence

### Bootstrap once

1. `terraform init`
2. Create ECR repositories only.
3. Build and push the four images.

ECR storage is small but not literally free; remove stale images if they accumulate.

### Run one planned cloud test window

1. Apply the complete stack shortly before the team is ready to test.
2. Confirm all three ALB target groups are healthy.
3. Run E1, E2, and E3. Run E4 and E5 if time permits during the same window.
4. Run the load generator only for the test window. Avoid leaving it running.
5. Download k6 JSON, CloudWatch CSV, screenshots, and graphs to `results/`.

### Tear down

After saving evidence:

```bash
CONFIRM_DESTROY=YES ./scripts/teardown.sh
```

Then check the AWS console for leftover resources outside Terraform: EBS volumes/snapshots, CloudWatch log groups, public IPv4 addresses, load generator instances, and any manually-created resources. Keep the source repository and result files locally; ECR and managed data resources are destroyed with the stack.

## Spend discipline

- Keep the complete stack up only for a planned test block. The ALB, RDS, and ElastiCache have hourly charges even when request traffic is zero; EC2 ASG instances and public IPv4 addresses also accrue usage while running.
- Do not leave ALB, RDS, ElastiCache, and EC2 running overnight just for a live URL. A brief live demonstration can be scheduled by recreating the stack.
- Do not create a NAT Gateway; it has an hourly charge even when idle.
- Do not create a load-generator EC2 instance until E1/E2 execution.
- Do not increase all three service ASGs to eight. E1 scales only search; E2's normal ceiling is two per service.
- Do not rely on the AWS Budget alert as a hard cap. Review Cost Explorer/Billing after each test day.
- Do not assume the full USD 100 is available for this project if the account has other usage.
- Check CPU-credit metrics for the burstable instances. The launch template uses the `cpu_credits` variable (credit-safe profile: `standard`, avoiding Unlimited surplus-credit charges; set `unlimited` for load-test runs where throttling would invalidate results); if CPU credits run out, performance can fall, so record the balance and keep runs finite.
- Use the [AWS Pricing Calculator](https://calculator.aws/) for the Mumbai region before extending the test window. Actual pricing changes and may include storage, data transfer, and public IPv4 charges.

## Important limitation

The Terraform stack still creates a public ALB, three small EC2 instances, a single-AZ RDS PostgreSQL instance, a one-node ElastiCache Redis cluster, SQS, ECR, VPC resources, and one CloudWatch dashboard. These are actual resources that consume credit while provisioned. The profile reduces instance scaling and optional resources; it does not make the managed services free.
