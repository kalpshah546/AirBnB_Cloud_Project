# Architecture and PoC mapping

## System under test

The project implements the following deliberately small Airbnb-style workload in `ap-south-1`:

- **Search service** (`/search`): builds a deterministic in-memory set of 50,000 synthetic listings, filters/ranks it, and performs bounded CPU work. It is intended to become CPU-bound under the holiday search burst.
- **Listing service** (`/listings/{id}`): reads listing detail from Redis first and PostgreSQL on a cache miss.
- **Booking service** (`/bookings`): records a unique idempotency key in PostgreSQL and, when `BOOKING_ASYNC=true`, submits the booking to SQS.
- **Booking worker**: consumes SQS messages and transitions a booking to `confirmed`. Duplicate message delivery only repeats an idempotent database update.
- **Monolith baseline** (`/monolith/search`, `/monolith/listings/{id}`, `/monolith/bookings`): exposes the same capabilities from one process and one Auto Scaling Group.

The three service ASGs and the monolith ASG share the same ALB. Path rules route each URL prefix to the corresponding target group. The EC2 instances are placed in public subnets because this low-cost teaching stack omits NAT gateways; their security group accepts application traffic only from the ALB. PostgreSQL and Redis are in private subnets. SQS and ECR calls leave the application instances through their public-subnet internet route.

## AWS resources

- VPC, two public subnets and two private subnets across two availability zones.
- Internet-facing Application Load Balancer and four target groups.
- Four EC2 Auto Scaling Groups, one for each service/monolith target group.
- ECR repositories for the four application images.
- RDS for PostgreSQL, one-node ElastiCache Redis cluster and an SQS booking queue.
- EC2 instance role with ECR read, SSM access and least-scope SQS permissions.
- CloudWatch dashboard and optional AWS Budget.

The infrastructure is intentionally a proof of concept, not a production Airbnb architecture. It uses HTTP, one RDS instance, one Redis node, no multi-AZ database failover, no NAT gateway, and a small single-AZ cache node. Do not put personal data or production credentials into it.

## Important measurement controls

1. Keep the same k6 traffic mix, data set, CPU work setting and instance type between comparable runs.
2. Use a load generator separate from the target EC2 instances; for final AWS measurements, use the optional same-region k6 EC2 runner.
3. Record both offered load and completed request rate. A closed workload may silently generate fewer requests as latency rises; the supplied k6 scripts use arrival-rate executors.
4. Wait for newly launched instances to pass ALB health checks before interpreting capacity. Record scale-out trigger time and first healthy-target time separately.
5. Cap PostgreSQL pool size with `db_pool_max`; total DB connections are approximately app instances × pool size, plus worker processes.
6. Report three runs and mean/standard deviation. Do not replace an inconvenient run without explaining why it was invalid.

## Assumptions

The workload and traffic values in the scripts are synthetic experimental inputs. They are not claimed to be Airbnb production request rates, host counts, cloud bills or measured holiday peaks. The architectural question is whether separating services reduces interference when only one workload is hot.
