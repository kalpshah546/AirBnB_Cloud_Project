# Two-week team implementation and Git plan

**Suggested window:** 16–30 November 2026. The dates are a work plan, not a request to fabricate timestamps. Commit when a task has genuinely been completed, reviewed and tested; move a task if the work is not ready.

## Work split

| Owner | Workstream | Main outputs | Experiments |
|---|---|---|---|
| Kalp Shah | AWS infrastructure | VPC/subnets/security groups, ALB/listener rules/target groups, launch templates, ECR, service and monolith ASGs, scaling policies, CloudWatch, budget/teardown | E2 |
| Vansh Vora | Backend/services | Search/listing/booking APIs, monolith variant, Postgres schema/indexes, Redis cache, SQS producer/worker, idempotency and tests | E3, E5 |
| Meet Gandhi | Test/measurement | k6 scenarios, load-generator setup, CloudWatch collector, CSV/plots, variance analysis and cost model | E1, E4, E6 |

## Suggested dated milestones

| Date | Kalp — infrastructure | Vansh — backend | Meet — testing/analysis |
|---|---|---|---|
| Nov 16 | Create AWS budget/quotas checklist; inspect Terraform modules | Review APIs and data model; run local tests | Review k6 scenarios and metric definitions |
| Nov 17 | Terraform provider, variables and VPC plan | Search endpoint and deterministic 50k data generator | E1 fixed-capacity script and thresholds |
| Nov 18 | Public/private subnet and security-group rules | Listing endpoint and Postgres schema/indexes | CloudWatch-to-CSV collector skeleton |
| Nov 19 | ALB, listener rules, target groups | Redis cache-aside and cache on/off switch | Plot p50/p95/p99 against instance count |
| Nov 20 | Launch template, ECR and search ASG | Booking endpoint and idempotency tests | Validate k6 request mix locally |
| Nov 21 | Listing and booking ASGs | SQS producer, worker and DB write path | E1 local dry run and report template |
| Nov 22 | CloudWatch dashboard and alarms | Compose integration tests across all services | E1 cloud run, 1/2/4/8 fixed-capacity points |
| Nov 23 | Review infra PRs and fix deployment issues | Add monolith route parity and tests | E1 reruns; calculate variation |
| Nov 24 | CPU target-tracking policy | Tune CPU work and connection-pool limits | E2 k6 holiday profile and runbook |
| Nov 25 | Step-scaling policy and cooldown/warm-up settings | Booking retry and duplicate-request tests | E2 run 1; capture request and metric data |
| Nov 26 | Scheduled pre-warm policy | E3 SOA-vs-monolith route parity checks | E2 runs 2 and 3; scaling-delay analysis |
| Nov 27 | Terraform apply/destroy rehearsal | E3 search-only spike and E5 queue-vs-direct tests | E3/E4/E5 analysis support and graphs |
| Nov 28 | Fix reproducibility and teardown issues | Integration tests, API docs and bug fixes | E6 cost per million requests and variance |
| Nov 29 | Final infrastructure PR and evidence | Final backend PR and README review | Final graph generation and report tables |
| Nov 30 | Final demo/rebuild rehearsal | Final demo/rebuild rehearsal | Freeze results, verify report and tag release |

## Suggested PR sequence

Keep changes reviewable rather than creating one giant project commit:

1. `chore: initialize repository and local development workflow`
2. `infra: add VPC and security group foundation`
3. `backend: add search service and deterministic listing data`
4. `test: add E1 fixed-capacity k6 scenario`
5. `infra: add ALB path routing and target groups`
6. `backend: add listing persistence and Redis cache`
7. `infra: add independent service Auto Scaling Groups`
8. `backend: add booking idempotency and SQS worker`
9. `infra: add CPU, step and scheduled scaling policies`
10. `test: add holiday spike and service-isolation scenarios`
11. `analysis: add CloudWatch collection and experiment plots`
12. `analysis: add cost-per-million-request model`
13. `docs: add measured results, limitations and viva runbook`

These are examples. A commit should only be made when its change exists and has been tested; a milestone may require several commits or fewer commits depending on actual work.

## Evidence to retain

- GitHub PRs and reviews showing the actual contributors.
- `git log --date=iso --pretty=fuller` for the commit timeline.
- k6 output files, CloudWatch exports and screenshots created during real runs.
- Experiment log entries with run date, configuration, git commit SHA, request count and outcome.
- A short contribution note from each member describing work they implemented, reviewed and can explain.
