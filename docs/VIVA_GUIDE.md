# Viva guide: what to show and how to explain it

## 0. The 60-second story (say this first)

"The assignment asks us to prove that infrastructure adds servers automatically when traffic spikes and removes them when traffic drops. I took my Airbnb-style search service, packaged it in Docker, and ran it on EC2 instances behind an AWS Application Load Balancer. An Auto Scaling Group watches average CPU and keeps it near 50%: above that it launches instances, below it removes them. I load-tested it with k6. One instance handled about 15 requests per second. When I sent 16 per second for ten minutes, CPU went to about 76%, the Auto Scaling Group launched a second and then a third instance, and the response time fell from about 700 ms back to about 200 ms. When traffic dropped, it removed the extra instances by itself."

## 1. What to show live (in this order)

> **Update: the AWS stack was destroyed on 17 Nov 2026 (52 resources), so the live URL below no longer works.** Use the screenshots and saved graphs instead, and follow `docs/VIVA_WORKFLOW.md` for the full plan (including how to rebuild a live URL if needed).

1. **The live URL** (worked only while the stack was up):
   `http://airbnb-soa-poc-alb-1748194001.ap-south-1.elb.amazonaws.com/search?city=Goa&limit=5`
   Say: "This goes through the load balancer, not directly to a server."
   - `/health` on the ALB gives 404 on purpose: only `/search`, `/listings`, `/bookings` are routed.
   - `/listings/1` gives 503 on the ALB: that service has 0 instances because of the 8-vCPU quota. Say so honestly.
2. **AWS console, EC2 → Load Balancers** → the ALB: DNS name, listener on port 80, rules.
3. **Target Groups → `airbnb-soa-poc-search-tg` → Targets**: healthy instances. Health check path `/health`.
4. **Auto Scaling Groups → `airbnb-soa-poc-search-asg`**:
   - Details: min 1, desired, max 3.
   - **Activity tab:** "Launching a new EC2 instance" (17:10:15 and 17:13:14) and "Terminating" (17:35:59, 17:37:00). This is the proof of automatic scaling. Click one and read the cause: "a monitor alarm TargetTracking-...-AlarmHigh in state ALARM".
   - **Automatic scaling tab:** target tracking, metric Average CPU utilization, target value 50.
5. **The graph** `reports/figures/e2_response_time_vs_instances.png`. Walk it left to right: green line = instances, red = p95 latency; latency rises while there is 1 instance, drops when instance 2 becomes healthy.
6. **The report** `reports/FINAL_REPORT.md` and the code in `infra/terraform/`.

If the stack has already been destroyed: show the saved graphs, the screenshots and `results/evidence/asg_scaling_activities.json`, and say it was destroyed to stop charges.

## 2. Key numbers to remember (all measured)

| Fact | Value |
|---|---|
| Instance type | t3.micro, 2 vCPU |
| ASG | min 1, desired 1, max 3 |
| Scaling rule | target tracking, average CPU 50% |
| One instance capacity | about 15 req/s (p95 about 200 ms) |
| E2 peak | 16 req/s for 10 min |
| Peak CPU with 1 instance | about 76% |
| p95 with 1 instance at peak | median 680 ms, worst 1,308 ms |
| p95 with 2 instances | median 257 ms |
| Scale-out events | 17:10:15 and 17:13:14 UTC |
| Scale-in events | 17:35:59 and 17:37:00 UTC (about 19 min after load fell) |
| E2 totals | 16,679 requests, 2 failed (0.01%), p95 623 ms |
| E1 | overloaded on purpose: health check failed, ASG replaced the instance |

## 3. Explain: the AWS pieces

- **VPC / subnets:** our own private network. Public subnets hold the ALB and instances; private subnets hold the database. No NAT gateway, to save money.
- **Security groups** = firewalls. ALB accepts port 80 from anywhere; instances accept port 8000 **only from the ALB**; the database accepts 5432 **only from the instances**. No SSH is open.
- **ALB (Application Load Balancer):** layer-7 load balancer. A listener on port 80 with path rules sends `/search*` to the search target group. It spreads requests across healthy instances and runs health checks.
- **Target group:** the list of instances behind the ALB. Health check `GET /health` every 20 s; 2 passes = healthy, 3 failures = unhealthy.
- **Launch template:** the recipe for a new instance: AMI, `t3.micro`, IAM role, security group, IMDSv2 required, and the **user-data script** that installs Docker, logs in to ECR, pulls the image and starts the container. This is why new instances start the app without anyone logging in.
- **Auto Scaling Group:** keeps between 1 and 3 instances running, registers them with the target group, and replaces unhealthy ones (health check type ELB).
- **Target tracking policy:** "keep average CPU at 50%". AWS creates two CloudWatch alarms itself (AlarmHigh and AlarmLow). High alarm fires after several consecutive 1-minute readings above target; low alarm needs about 15 minutes below to scale in.
- **Warm-up (120 s):** time a new instance is ignored when computing average CPU, so it is not counted before it is serving.
- **CloudWatch:** metrics (CPU, instance counts, ALB metrics) and alarms.
- **ECR:** private Docker registry holding our images. The instance role has read-only access to it.
- **RDS PostgreSQL:** one shared database for all instances; that is what keeps data consistent when there are several servers.
- **IAM:** a role for instances (ECR read + SSM); a separate IAM user for me. Never use the root account for work.
- **IMDSv2:** a more secure way for software on the instance to read instance metadata; required in the launch template.
- **Terraform:** infrastructure as code. `terraform plan` shows what will change, `apply` creates it, `destroy` removes it. State is stored locally (so only one person should run it).

## 4. Explain: scaling behaviour

- **Scale-out is not instant:** CPU must stay above 50% for a few minutes, then the instance boots, pulls the image and passes two health checks. In my run: CPU crossed 50% about 17:07, instance launched 17:10:15, healthy 17:12:20. Users saw slower responses in between.
- **Scale-in is slow on purpose:** to avoid adding and removing servers repeatedly.
- **Why two instances became three:** the high alarm was still in the ALARM state when it re-evaluated, even though CPU had fallen to about 45%. (I did not verify the alarm history, say "likely".)
- **The E1 failure:** at 19 req/s one instance fell behind, its health check failed, and the ASG replaced it and launched an extra one. It shows autoscaling reacting to failure, and also shows why you should scale **before** instances saturate.
- **Why latency includes about 130 ms even when idle:** about 80 ms of deliberate CPU work per search request plus the internet path from my laptop.

## 5. Docker: commands to know

```bash
docker build -f services/search/Dockerfile -t airbnb-search .   # build an image
docker images                          # list images
docker run -d --name app -p 8000:8000 --env-file app.env airbnb-search   # run detached, map port, load env
docker ps                              # running containers
docker ps -a                           # include stopped
docker logs app                        # view container output (first debugging step)
docker logs -f --tail 50 app           # follow the last 50 lines
docker exec -it app sh                 # shell inside the container
docker stop app && docker rm app       # stop and remove
docker compose up -d --build           # start the whole multi-container stack
docker compose ps                      # status of stack
docker compose logs search             # logs of one service
docker compose down                    # stop and remove stack
docker login / push / pull             # registry operations (here ECR)
```

**Dockerfile (services/search/Dockerfile):** `FROM python:3.12-slim` (base image) → `WORKDIR /app` → `COPY requirements.txt` + `pip install` (dependencies first so Docker caches that layer) → `COPY services /app/services` → `EXPOSE 8000` (documentation of the port) → `CMD ["uvicorn", "services.search.app:app", "--host", "0.0.0.0", "--port", "8000"]` (start the web server; `0.0.0.0` so it is reachable from outside the container).

**Why `WEB_CONCURRENCY=2`:** Python handles one request at a time per process (GIL). A `t3.micro` has 2 vCPUs, so 2 worker processes are needed to use both. With 1 worker, CPU could never pass about 50% and autoscaling would never trigger.

**How ECR is used on AWS:**
```bash
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin <acct>.dkr.ecr.ap-south-1.amazonaws.com
docker build --platform linux/amd64 -t <acct>.dkr.ecr.ap-south-1.amazonaws.com/airbnb-soa-poc-search:latest .
docker push <that same tag>
```
`--platform linux/amd64` because EC2 `t3` is x86 (a laptop might be ARM).

**docker-compose files:** `compose.yaml` = full local stack (postgres, redis, localstack/SQS, 3 services, workers, monolith, nginx gateway on port 8080). `compose.prod.yaml` = the lean single-server version used on the separate demo EC2.

## 6. Nginx: what to explain

File `nginx/nginx.conf` (local) and `nginx.prod.conf` (demo server). Nginx is a **reverse proxy / API gateway**:

```nginx
server { listen 80;
  location /search   { proxy_pass http://search:8000; }    # route by URL path to a service
  location /listings { proxy_pass http://listing:8000; }
  location /bookings { proxy_pass http://booking:8000; }
}
```
- `proxy_pass` forwards the request to the container named `search` on Docker's internal network; clients never see port 8000.
- `proxy_set_header X-Forwarded-For` passes the real client IP to the app.
- On AWS the **ALB does this job** (path-based routing), so Nginx is not used in the autoscaling stack. In both cases the idea is the same: one public entry point, several services behind it.
- Commands: `nginx -t` (test config), `nginx -s reload` (reload), `docker compose logs gateway`.

## 7. Terraform: commands and files

```bash
terraform init        # download providers
terraform fmt         # format
terraform validate    # check syntax
terraform plan        # preview (no changes)
terraform apply       # create / update
terraform output      # print outputs (the ALB URL)
terraform state list  # resources Terraform manages
terraform destroy     # remove everything it created
```
Files: `versions.tf` (provider), `variables.tf` (inputs), `network.tf` (VPC, subnets, security groups), `compute.tf` (ALB, launch template, ASG, scaling policy, dashboard), `data.tf` (ECR, RDS, SQS), `outputs.tf`. `terraform.tfvars` holds my values and is gitignored.

## 8. AWS CLI commands worth knowing

```bash
aws sts get-caller-identity                          # who am I (must NOT be root)
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names airbnb-soa-poc-search-asg
aws autoscaling describe-scaling-activities --auto-scaling-group-name airbnb-soa-poc-search-asg   # the scale-out/in history
aws elbv2 describe-target-health --target-group-arn <arn>      # which instances are healthy
aws ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name]'
aws cloudwatch get-metric-statistics ...             # CPU etc.
```

## 9. k6 load testing: what to explain

- k6 runs JavaScript test scripts. `ramping-arrival-rate` sends a set number of requests per second no matter how slowly the server answers (like real users arriving), unlike a fixed number of virtual users.
- Scripts: `loadtest/k6/fixed-capacity.js` (E1 ramp), `search-spike.js` (E2 spike), `holiday-spike.js` (original mixed spike).
- Output: `--out csv=` saves every request; `--summary-export` saves totals. p95 = 95% of requests were faster than this.
- `scripts/monitor-asg.sh` samples instance counts every 15 s so latency can be matched to instance count.

## 10. Likely questions and honest answers

**Q: Why did you only deploy the Search service?**
The account's EC2 quota is 8 vCPU; the demo server takes 2, leaving room for three `t3.micro` instances. Search is the CPU-bound service, so it demonstrates CPU scaling. Listing and Booking were not deployed on the ALB and I did not test them there.

**Q: Why not just copy the Docker Compose stack onto every instance?**
Each copy would have its own database, so bookings would differ between servers. A shared RDS database keeps state consistent.

**Q: Why is Redis off?**
It is only a read cache, so correctness does not depend on it, and it costs about $0.02 per hour.

**Q: Why t3 and not t2?**
t2 throttles CPU to a small baseline once burst credits run out, which would corrupt load-test results. I used `unlimited` credit mode so CPU is not throttled.

**Q: Did the scaling really happen automatically?**
Yes: I did not change capacity by hand. The Activity history shows each launch with the cause "AlarmHigh ... ALARM". The data is saved in `results/evidence/asg_scaling_activities.json`.

**Q: What are the weaknesses of the test?**
One run per experiment; traffic from one home connection (latency includes the internet path); the 3-instance result is one 30-second window; peak load is small; listing/booking untested on the ALB; one unexplained latency spike at 17:24:45.

**Q: What went wrong during testing?**
E1 overloaded one instance past its capacity; its health check failed and the ASG replaced it. Also my first `terraform apply` failed because my IAM user lacked `iam:CreateRole`, and the Auto Scaling service-linked role needed a minute to propagate. I fixed the permissions and re-ran.

**Q: How much does it cost and how do you stop it?**
About $0.10–0.16 per hour while running (estimate). `terraform destroy` removes it. Leaving it up for a month would use roughly the whole $100 credit.

**Q: How is it secured?**
No SSH; instances reachable only from the ALB; database only from instances and not public; IMDSv2 required; IAM role with minimal permissions; secrets not in Git.

**Q: How would this scale for a real event like IRCTC?**
Higher max capacity, a lower target CPU (for example 40%) or step scaling and **scheduled pre-warming** before known events, since reactive scaling lags by minutes; add caching (Redis), a bigger or replicated database, HTTPS and multiple AZs. The repository already has scheduled and step scaling modes in Terraform that I did not test.

**Q: You used Nginx in one place and the AWS load balancer in another. What is the difference?**
Both are reverse proxies that spread requests over several backends. On AWS the managed Application Load Balancer is paired with the Auto Scaling Group, which decides how many instances exist; it adds health checks, connection draining and multi-AZ. In the local Docker demo, Nginx plays the same role but Docker has no autoscaler, so my own script (`scripts/docker-autoscaler.sh`) decides how many containers run. Kubernetes autoscaling was not implemented. Details: `reports/DOCKER_AUTOSCALING_GUIDE.md`.
