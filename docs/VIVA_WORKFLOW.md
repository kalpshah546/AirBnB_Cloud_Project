# Viva workflow: from scratch, what to prepare, show and say

**Situation at viva time:** the AWS assignment stack has been **destroyed** (to stop charges), so the live ALB URL no longer works. You show **saved evidence** from the AWS run, plus a **live Docker autoscaling demo** on your own laptop. Optionally you can rebuild the AWS stack (Section 6) if the examiners insist on a live URL.

Total time plan: **about 15 minutes** of presenting, leaving time for questions.

---

## 1. Before the viva (the day before)

### Files to have open or ready
| What | Where |
|---|---|
| Final report (PDF) | `reports/FINAL_REPORT.pdf` |
| Key graph | `reports/figures/e2_response_time_vs_instances.png` |
| Other graphs | `reports/figures/e2_cpu_over_time.png`, `e2_instance_count_over_time.png`, `e2_p95_by_instance_count.png`, `e1_latency_vs_rate.png` |
| AWS screenshots | `screenshots/` (ALB URL, target group healthy, **ASG Activity tab**, scaling policy 50%) |
| ASG activity history (raw proof) | `results/evidence/asg_scaling_activities.json` |
| Docker guide + graphs | `reports/DOCKER_AUTOSCALING_GUIDE.pdf`, `reports/figures/docker_p8_*.png` |
| Terraform code | `infra/terraform/compute.tf` (ALB, launch template, ASG, scaling policy) |
| Backups of big raw files | `e1_requests.csv`, `e2_requests.csv`, `docker_p5/p8_requests.csv` (not in Git) |
| This guide and Q&A | `docs/VIVA_GUIDE.md` |

### Laptop checks (do them once, the night before)
```bash
cd ~/AirBnB_Cloud_Project && git pull origin aws-deploy-fixes
docker --version && k6 version               # both must work
docker compose -p airbnb-autoscale -f docker/compose.autoscale.yaml up -d --build   # pre-build the image
docker compose -p airbnb-autoscale -f docker/compose.autoscale.yaml down -v
```
Pre-building matters: the first build takes a minute or two.

### Memorize these 8 numbers
1. Instance: `t3.micro`, 2 vCPU. ASG: min **1**, max **3**. Rule: average CPU **50%**.
2. One instance capacity: about **15 requests/s** (E1).
3. E2 spike: 4 → **16 req/s**, held 10 min.
4. CPU with one instance at peak: about **76%**.
5. p95 latency: **680 ms** (1 instance) → **257 ms** (2 instances).
6. Scale-out at **17:10:15** and **17:13:14** UTC; scale-in at **17:35:59** and **17:37:00**.
7. E2 totals: 16,679 requests, **2 failed**.
8. Quota: **8 vCPU** minus 2 for the demo server = 3 `t3.micro` → only Search deployed.

---

## 2. The presentation script (15 minutes)

### Minute 0–2: the problem and the idea
Say: "During a holiday or sale, traffic jumps many times. Fixed servers are too few during the spike or wasted afterwards. I built a setup where servers are added automatically when CPU passes 50% and removed when traffic drops."
Show: first page of the report (objective + deliverables table).

### Minute 2–5: the architecture
Show: the architecture diagram in the report (Section 2).
Say, left to right: "Users go to an **Application Load Balancer**. It sends `/search` requests to a **target group** that health-checks each server. The servers are **EC2 instances created by an Auto Scaling Group** from a **launch template** that installs Docker and pulls my container from **ECR**. For the full application, the Listing and Booking servers would all use one shared **RDS PostgreSQL** database so data stays consistent. In my test only the Search service ran, and Search builds its listings in memory and never touches the database, so the RDS instance I created was idle. I should have left it out of the test."
Open `infra/terraform/compute.tf` and point to: the ALB, the launch template (IMDSv2, user-data), the ASG (min 1, max 3), and the **target tracking policy with target value 50**.
Say: "All of it is Terraform, so it can be rebuilt with one command."

### Minute 5–7: the live URL (Deliverable 1)
Show: screenshot `screenshots/01-alb-url-response.png` (or the live URL if you rebuilt the stack).
Say: "This is the ALB DNS name answering `/search` with JSON. I destroyed the stack afterwards to stop the charges; the Terraform code rebuilds it in about 25 minutes."
Show: `04-target-group-healthy.png` (healthy targets).

### Minute 7–11: the proof of autoscaling (the main part)
1. Show `reports/figures/e2_response_time_vs_instances.png`. Walk it: "Green = number of healthy instances. Red = p95 response time. With 1 instance the latency climbs to over a second. When the ASG adds instance 2 at 17:10, latency falls back to about 270 ms. A third instance follows. After traffic drops, the instances are removed."
2. Show `e2_cpu_over_time.png`: "CPU sat at about 76%, above the 50% line, which triggered scaling."
3. Show the **ASG Activity screenshot** (`05-asg-activity-scale-out.png`): "Launching a new EC2 instance, with the cause: alarm AlarmHigh in state ALARM. I did not launch these by hand."
4. Show the table "response time by instance count": 1 instance 680 ms, 2 instances 257 ms.
5. Show the scaling policy screenshot (`07-asg-scaling-policy-50.png`): "Target tracking, 50."
Say the honest points: "One run; the 3-instance number is a single 30-second window; there was a lag of about 5 minutes between CPU crossing 50% and the second instance serving traffic; scale-in takes about 19 minutes by design."

### Minute 11–12: E1 and the failure
Show `e1_latency_vs_rate.png`.
Say: "E1 found one instance handles about 15 req/s. I pushed it to 19 and beyond; the health check failed and the ASG replaced the instance automatically. That is also a real autoscaling event, but I did not use it for the main graph because it mixes overload and failure."

### Minute 12–15: live Docker demo (Docker + Nginx autoscaling)
Say: "This is the same idea on my laptop, with **Nginx as the load balancer**. Docker has no autoscaler of its own, so I wrote a small script that does what the AWS policy does."
Run the **short demo** (about 4 minutes):

```bash
# before the viva starts, with the stack down, run this to start:
docker compose -p airbnb-autoscale -f docker/compose.autoscale.yaml up -d --build
curl http://localhost:18081/health

# Terminal A: autoscaler (short scale-in wait so the demo finishes)
DOWN_STABLE=30 ./scripts/docker-autoscaler.sh

# Terminal B: load (about 3.5 minutes)
k6 run -e BASE_URL=http://localhost:18081 -e NORMAL_RPS=1 -e PEAK_RPS=8 \
  -e WARM_S=10 -e RAMP_S=20 -e HOLD_S=120 -e DOWN_S=10 -e COOL_S=60 loadtest/k6/search-spike.js

# Terminal C: watch containers appear
watch -n 2 'docker compose -p airbnb-autoscale -f docker/compose.autoscale.yaml ps'
```
Point at: terminal A showing `scale_out` with CPU above 50, terminal C showing 2 to 4 `search` containers, then `scale_in` back to 1.
Show: the recorded graph `docker_p8_response_time_vs_containers.png` and say: "Latency barely changed locally because this laptop is fast; the AWS run is the one that shows the big latency effect."
Close: `docker compose -p airbnb-autoscale -f docker/compose.autoscale.yaml down -v`.

> **Backup plan if the live demo fails** (Docker not starting, port busy): show the saved Docker graphs and the autoscaler CSV in `results/evidence/docker_p8_autoscale_samples.csv` and explain the data.

---

## 3. What each tool is, in one line (for the explaining parts)

- **Docker:** packages the app and its dependencies into an image that runs the same everywhere. `docker build`, `docker run`, `docker ps`, `docker logs`, `docker compose up -d`.
- **Dockerfile:** recipe for the image (`FROM python:3.12-slim`, copy code, `pip install`, `CMD uvicorn ...`).
- **Nginx:** reverse proxy and load balancer. It receives requests on one address and forwards them to the app containers.
- **ECR:** private registry where the image is stored so EC2 instances can pull it.
- **EC2 / Launch template / ASG:** the virtual servers; the recipe for a server; the manager that keeps 1–3 servers and adds or removes them by rule.
- **ALB + target group:** the load balancer, and the list of healthy servers behind it.
- **CloudWatch:** metrics and alarms (CPU). The 50% rule is two CloudWatch alarms that AWS creates for you.
- **RDS:** managed PostgreSQL. Used by Listing and Booking; the Search service (the only one deployed in the test) does not use it, so it sat idle.
- **Terraform:** infrastructure as code: `init`, `plan`, `apply`, `destroy`.
- **k6:** load-testing tool. A virtual user runs the test function in a loop. I used an **open model** (`ramping-arrival-rate`): a fixed number of requests per second, whatever the server does. See `reports/DOCKER_AUTOSCALING_GUIDE.md` Section 3.

---

## 4. Questions to be ready for (short answers)

- **Why only Search?** 8-vCPU quota; demo uses 2; room for 3 `t3.micro`; Search is the CPU-bound service. Listing/Booking were not tested on the ALB.
- **Did it really scale automatically?** Yes; the Activity history shows the alarm cause for each launch. Nobody changed capacity by hand.
- **Why a shared database?** For Listing and Booking: otherwise each server would have its own bookings. **Be honest that Search doesn't use the database** (it generates its 50,000 listings in memory at startup and burns about 80 ms of CPU per request), so in the AWS test the RDS instance was created but idle and cost a little for nothing.
- **Where is the app code and database?** Code: `services/` (search, listing, booking, monolith, common). Database: PostgreSQL; the tables (`listings`, `bookings`) are created by the code in `services/common/db.py` and filled with 50,000 generated listings by `services/common/data.py`. No SQL file exists and the data is fake.
- **Why `t3` not `t2`?** `t2` throttles CPU when credits run out, which would corrupt the test.
- **Why 2 workers?** Python uses one CPU core per process; with 1 worker CPU could never reach 50% on a 2-vCPU server, so scaling would never trigger.
- **Does Docker autoscale?** No. My script decides; Docker only runs N copies.
- **Biggest weaknesses?** One run; home internet adds latency; scale-out lag; flapping in Docker run 1; unexplained spike at 17:24:45.
- **Cost?** About $0.10–0.16 per hour (estimate); destroyed afterwards.
- **What went wrong?** E1 overload; IAM permission missing on first apply; a propagation delay on the Auto Scaling service-linked role.
- More: `docs/VIVA_GUIDE.md` section 10.

---

## 5. What not to claim (avoid over-claiming)

- Do not say Listing/Booking were tested on AWS. They were not deployed there.
- Do not say Docker autoscales by itself or that Kubernetes was done. It was not.
- Do not present estimates (cost, "users") as measurements. The report labels them.
- Do not say the live URL still works; the stack was destroyed.

---

## 6. If the examiners want a live AWS URL (optional, about 30 minutes, about $0.10–0.16/h)

From WSL, in `~/AirBnB_Cloud_Project`, with the IAM user (not root) configured and the extra IAM permissions still attached:

```bash
export AWS_PROFILE=assignment && aws sts get-caller-identity       # must show user/airbnb_project
cp infra/terraform/terraform.tfvars.assignment.example infra/terraform/terraform.tfvars   # set create_budget = false
cd infra/terraform && terraform init
terraform apply -var-file=terraform.tfvars -target=aws_ecr_repository.images
cd ../.. && ./scripts/build-push.sh
cd infra/terraform && terraform apply -var-file=terraform.tfvars      # 10-15 min; re-run once if a service-linked-role error appears
terraform output alb_base_url
```
Then open `<url>/search?city=Goa&limit=5` (a 502 for the first few minutes is normal) and **destroy afterwards**:
```bash
terraform destroy -var-file=terraform.tfvars
```
Start this **at least an hour before** the viva. A fresh stack has a new URL, so show the saved graphs as "the 17 Nov run".
