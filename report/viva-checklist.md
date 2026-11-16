# Viva checklist

Every team member should be able to explain and demonstrate:

1. How ALB path-based routing sends `/search`, `/listings`, `/bookings` and `/monolith/*` to target groups.
2. Why the search route is CPU-heavy and how `search_cpu_work_ms` was calibrated.
3. How CPU target tracking, step scaling and scheduled pre-warm differ.
4. The difference between an instance launched and an instance passing the ALB health check.
5. How Redis cache-aside works and why PostgreSQL remains the source of truth.
6. How the idempotency key and unique database constraint prevent duplicate booking rows on retry.
7. Why SQS delivery is at-least-once and why worker updates must be idempotent.
8. What p50, p95 and p99 mean; why p95 is useful for a user-facing service.
9. How instance-seconds and cost per one million successful requests are calculated, and what costs are excluded.
10. Which values are synthetic assumptions versus Airbnb facts supported by primary sources.

Bring a short recorded demo as backup, but retain the live ALB URL, CloudWatch evidence and raw test outputs for questions.
