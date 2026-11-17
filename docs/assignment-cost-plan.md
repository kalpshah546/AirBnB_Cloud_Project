# Assignment stack: cost and architecture decisions

All prices are **estimates** (ap-south-1, on-demand, approximate; verify on the AWS pricing pages). Nothing here is measured.

> **Correction (found after the experiment):** the Search service, the only one deployed in the test, does not use
> PostgreSQL at all (it builds its listings in memory). The RDS instance in this plan was therefore idle during the
> test; it matters only for Listing and Booking. A Search-only run could have skipped RDS and saved about $0.02/h.

## Why shared state is required (for Listing and Booking)
Search keeps no state at all, but bookings and listings live in Postgres. Copying the Docker Compose stack
onto each ASG instance would give every instance its own empty database, so scaled instances would disagree.
The ASG instances therefore share one Postgres. Redis is only a cache-aside read cache and can be dropped.

## Shared database options
| Option | ~Cost | Trade-off |
|---|---|---|
| RDS db.t3.micro, single-AZ (chosen) | ~$0.02/h + ~$2/mo storage | Managed, simple, survives instance churn |
| Postgres in Docker on one extra t3.micro | ~$0.012/h | Slightly cheaper, but self-managed, data lost with the instance, extra bootstrap code |
| Aurora Serverless / multi-AZ RDS | higher | Not justified for a short experiment |

## Redis
ElastiCache cache.t3.micro ~ $0.02/h. Disabled in the assignment profile (`create_redis = false`): no loss of correctness.

## Hourly estimate while the stack is up (ASG at 1/1/1, search scaling to 3)
| Item | ~$/h |
|---|---|
| ALB | 0.03 |
| RDS db.t3.micro | 0.02 |
| 3 baseline t3.micro (+2 at peak) | 0.035 (0.058) |
| Public IPv4 (instances + 2 ALB addresses) | 0.035 – 0.05 |
| **Total** | **~0.12 – 0.16** |

A 6-hour session is therefore roughly $1; leaving it up for a month would be ~ $90-110, i.e. all the credit.
No NAT gateway is used (instances are in public subnets behind a security group that only allows the ALB).
Budget alerts at 50/75/90% are alerts, not a spending cap. Destroy the stack after collecting evidence.

## vCPU quota
Peak = search 3 + listing 1 + booking 1 = 5 instances = 10 vCPU (t3.micro = 2 vCPU). Check the
"Running On-Demand Standard instances" quota; a request for an increase needs explicit approval.
