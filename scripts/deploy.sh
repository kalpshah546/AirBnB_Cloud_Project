#!/usr/bin/env bash
# Full AWS deployment of the Airbnb SOA PoC, end to end:
#   preflight checks -> ECR -> build & push images -> full Terraform apply
#   -> (re)roll instances if images changed -> wait for healthy ALB targets -> smoke tests -> save outputs.
#
# Usage (from anywhere inside the repo, in WSL):
#   ./scripts/deploy.sh                 # first deploy, or redeploy after code changes
#   SKIP_BUILD=1 ./scripts/deploy.sh    # only Terraform changes (e.g. scaling_mode), reuse pushed images
#   AUTO_APPROVE=1 ./scripts/deploy.sh  # skip the "apply this plan?" prompt
#
# Tear down after every work session:  cd infra/terraform && CONFIRM_DESTROY=YES ../../scripts/teardown.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/infra/terraform"
TFVARS="$TF_DIR/terraform.tfvars"
OUT_DIR="$ROOT/results/deploy"
HEALTH_TIMEOUT_SECONDS="${HEALTH_TIMEOUT_SECONDS:-1200}"
SKIP_BUILD="${SKIP_BUILD:-0}"
AUTO_APPROVE="${AUTO_APPROVE:-0}"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  OK  %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  WARN %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
tf()   { terraform -chdir="$TF_DIR" "$@"; }
tfvar() { # read a simple `key = value` line from terraform.tfvars (quotes stripped)
  sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"?([^\"#]*)\"?.*/\1/p" "$TFVARS" | head -1 | sed 's/[[:space:]]*$//'
}
json_get() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[sys.argv[1]])' "$1"; }

# ---------------------------------------------------------------- 1. tools
log "1/9 Checking local tools"
for tool in aws terraform docker python3 curl; do
  command -v "$tool" >/dev/null 2>&1 || die "'$tool' is not installed. Run ./scripts/install-tools-wsl.sh first."
done
docker info >/dev/null 2>&1 || die "Docker daemon not reachable. Start Docker Desktop and enable WSL integration."
ok "aws, terraform, docker, python3, curl present"
case "$ROOT" in
  /mnt/*) warn "Repo is on a Windows drive ($ROOT). Builds are much slower there; clone it into ~ inside WSL." ;;
esac

# ---------------------------------------------------------------- 2. tfvars
log "2/9 Checking terraform.tfvars"
if [[ ! -f "$TFVARS" ]]; then
  cp "$TF_DIR/terraform.tfvars.example" "$TFVARS"
  die "Created $TFVARS from the example. Set budget_alert_email (and max_capacity if your quota is low), then re-run."
fi
INSTANCE_TYPE="$(tfvar instance_type)"; INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
MAX_CAP="$(tfvar max_capacity)"; MAX_CAP="${MAX_CAP:-8}"
if [[ "$INSTANCE_TYPE" == t2.* ]]; then
  die "instance_type is $INSTANCE_TYPE. Use t3.micro: t2 CPU-credit throttling invalidates load tests."
fi
if [[ "$(tfvar create_budget)" == "true" ]]; then
  BUDGET_EMAIL="$(tfvar budget_alert_email)"
  if [[ -z "$BUDGET_EMAIL" || "$BUDGET_EMAIL" == CHANGE_ME* ]]; then
    die "Set budget_alert_email in terraform.tfvars (or set create_budget = false)."
  fi
fi
TF_REGION="$(tfvar aws_region)"; export AWS_REGION="${TF_REGION:-${AWS_REGION:-ap-south-1}}"
export AWS_DEFAULT_REGION="$AWS_REGION"
TF_PROJECT="$(tfvar project_name)"; export PROJECT_NAME="${TF_PROJECT:-airbnb-soa-poc}"
ok "region=$AWS_REGION project=$PROJECT_NAME instance_type=$INSTANCE_TYPE max_capacity=$MAX_CAP"

# ---------------------------------------------------------------- 3. AWS account + quota
log "3/9 Checking AWS credentials and EC2 vCPU quota"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" \
  || die "AWS credentials not configured or expired. Run: aws configure"
ok "AWS account $ACCOUNT_ID"

VCPU_PER_INSTANCE="$(aws ec2 describe-instance-types --instance-types "$INSTANCE_TYPE" \
  --query 'InstanceTypes[0].VCpuInfo.DefaultVCpus' --output text 2>/dev/null || echo 2)"
# Worst realistic case during experiments: search at max + listing/booking scaled to 2 each + k6 t3.small.
NEED_VCPU=$(( (MAX_CAP + 4) * VCPU_PER_INSTANCE + 2 ))
QUOTA="$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A \
  --query 'Quota.Value' --output text 2>/dev/null || echo unknown)"
if [[ "$QUOTA" == "unknown" ]]; then
  warn "Could not read the EC2 vCPU quota. Check Service Quotas -> EC2 -> 'Running On-Demand Standard instances'."
else
  QUOTA_INT="${QUOTA%.*}"
  if (( QUOTA_INT < NEED_VCPU )); then
    warn "vCPU quota is $QUOTA_INT, experiments may need ~$NEED_VCPU ($INSTANCE_TYPE = $VCPU_PER_INSTANCE vCPU each)."
    warn "Scale-out will silently stop at the quota. Request an increase to 32, or lower max_capacity."
  else
    ok "vCPU quota $QUOTA_INT >= ~$NEED_VCPU needed"
  fi
fi

# ---------------------------------------------------------------- 4. terraform init + ECR
log "4/9 terraform init + ECR repositories"
tf init -input=false >/dev/null
ok "terraform initialised"

ASG_EXISTED=0
if aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "${PROJECT_NAME}-search-asg" \
     --query 'length(AutoScalingGroups)' --output text 2>/dev/null | grep -q '^1$'; then
  ASG_EXISTED=1
fi

tf apply -input=false -auto-approve -var-file=terraform.tfvars -target=aws_ecr_repository.images >/dev/null
ok "ECR repositories ready"

# ---------------------------------------------------------------- 5. images
if [[ "$SKIP_BUILD" == "1" ]]; then
  log "5/9 Skipping image build (SKIP_BUILD=1)"
else
  log "5/9 Building and pushing images to ECR (first build takes a few minutes)"
  "$ROOT/scripts/build-push.sh"
  ok "images pushed"
fi

# ---------------------------------------------------------------- 6. full apply
log "6/9 Terraform plan + apply (VPC, ALB, ASGs, RDS, Redis, SQS, dashboard). RDS creation takes ~5-10 min."
tf plan -input=false -var-file=terraform.tfvars -out=tfplan
if [[ "$AUTO_APPROVE" != "1" ]]; then
  read -r -p "Apply this plan? Resources start billing immediately. [yes/N] " answer
  [[ "$answer" == "yes" ]] || { rm -f "$TF_DIR/tfplan"; die "Aborted by user."; }
fi
tf apply -input=false tfplan
rm -f "$TF_DIR/tfplan"
ok "infrastructure applied"

ASGS_JSON="$(tf output -json autoscaling_group_names)"
TGS_JSON="$(tf output -json target_group_arns)"
BASE_URL="$(tf output -raw alb_base_url)"

# Running instances only pull :latest at boot, so roll them when new images were pushed.
if [[ "$ASG_EXISTED" == "1" && "$SKIP_BUILD" != "1" ]]; then
  log "6b/9 Existing deployment + new images: starting instance refresh"
  "$ROOT/scripts/refresh-asgs.sh" || warn "Instance refresh could not start (one may already be running)."
  sleep 30
fi

# ---------------------------------------------------------------- 7. wait for healthy targets
log "7/9 Waiting for healthy ALB targets (timeout ${HEALTH_TIMEOUT_SECONDS}s; first boot + DB seeding ~4-8 min)"
deadline=$(( $(date +%s) + HEALTH_TIMEOUT_SECONDS ))
for service in search listing booking monolith; do
  asg="$(json_get "$service" <<<"$ASGS_JSON")"
  tg="$(json_get "$service" <<<"$TGS_JSON")"
  desired="$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$asg" \
    --query 'AutoScalingGroups[0].DesiredCapacity' --output text)"
  if [[ "$desired" == "0" ]]; then
    ok "$service: desired capacity 0 (expected for the monolith outside E3), skipping"
    continue
  fi
  while true; do
    healthy="$(aws elbv2 describe-target-health --target-group-arn "$tg" \
      --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' --output text)"
    if (( healthy >= desired )); then
      ok "$service: $healthy/$desired targets healthy"
      break
    fi
    if (( $(date +%s) > deadline )); then
      aws elbv2 describe-target-health --target-group-arn "$tg" \
        --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason,TargetHealth.Description]' --output table || true
      die "$service targets not healthy in time. Debug: AWS console -> EC2 -> instance -> Connect -> Session Manager, then: sudo docker logs app ; sudo cat /var/log/cloud-init-output.log"
    fi
    printf '  ... %s: %s/%s healthy\n' "$service" "$healthy" "$desired"
    sleep 20
  done
done

# ---------------------------------------------------------------- 8. smoke tests through the ALB
log "8/9 Smoke tests against $BASE_URL"
mkdir -p "$OUT_DIR"
fail=0
http_get() { curl -sS --max-time 30 --retry 5 --retry-delay 5 --retry-all-errors "$@"; }

code="$(http_get -o "$OUT_DIR/search.tmp" -w '%{http_code}' "$BASE_URL/search?city=Goa&limit=3" 2>/dev/null || echo 000)"
if [[ "$code" == "200" ]] && grep -q '"service":"search"' "$OUT_DIR/search.tmp"; then ok "GET /search -> 200"; else warn "GET /search -> $code"; fail=1; fi

first="$(http_get "$BASE_URL/listings/1" 2>/dev/null || true)"
second="$(http_get "$BASE_URL/listings/1" 2>/dev/null || true)"
if grep -q '"id":1' <<<"$first"; then ok "GET /listings/1 -> found"; else warn "GET /listings/1 failed: ${first:0:200}"; fail=1; fi
if grep -q '"cache":"hit"' <<<"$second"; then ok "Redis cache-aside -> second read is a cache hit"; else warn "Second /listings/1 read was not a cache hit (fine if cache_enabled=false): ${second:0:200}"; fi

KEY="deploy-smoke-$(date +%s)"
BODY='{"listing_id":1,"guest_id":"smoke-guest","check_in":"2027-05-01","check_out":"2027-05-03","guest_count":2}'
b1="$(http_get -X POST "$BASE_URL/bookings" -H 'Content-Type: application/json' -H "Idempotency-Key: $KEY" -d "$BODY" 2>/dev/null || true)"
b2="$(http_get -X POST "$BASE_URL/bookings" -H 'Content-Type: application/json' -H "Idempotency-Key: $KEY" -d "$BODY" 2>/dev/null || true)"
id1="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("booking_id",""))' "$b1" 2>/dev/null || true)"
id2="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("booking_id",""))' "$b2" 2>/dev/null || true)"
if [[ -n "$id1" && "$id1" == "$id2" ]]; then
  ok "POST /bookings twice with one Idempotency-Key -> same booking_id ($id1)"
else
  warn "Idempotency check failed. first=${b1:0:200} second=${b2:0:200}"; fail=1
fi
rm -f "$OUT_DIR/search.tmp"

# ---------------------------------------------------------------- 9. save outputs
log "9/9 Saving deployment outputs"
mkdir -p "$OUT_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
{
  echo "{"
  echo "  \"deployed_at_utc\": \"$STAMP\","
  echo "  \"account_id\": \"$ACCOUNT_ID\","
  echo "  \"region\": \"$AWS_REGION\","
  echo "  \"instance_type\": \"$INSTANCE_TYPE\","
  echo "  \"scaling_mode\": \"$(tfvar scaling_mode)\","
  echo "  \"alb_base_url\": \"$BASE_URL\","
  echo "  \"autoscaling_group_names\": $ASGS_JSON,"
  echo "  \"cloudwatch_dashboard\": \"$(tf output -raw cloudwatch_dashboard_name)\","
  echo "  \"load_generator_instance_id\": \"$(tf output -raw load_generator_instance_id 2>/dev/null || true)\""
  echo "}"
} > "$OUT_DIR/deploy-$STAMP.json"
cp "$OUT_DIR/deploy-$STAMP.json" "$OUT_DIR/latest.json"

# Ready-to-source env file for the experiment scripts.
cat > "$OUT_DIR/env.sh" <<ENV
# source results/deploy/env.sh   (generated $STAMP)
export AWS_REGION="$AWS_REGION"
export BASE_URL="$BASE_URL"
export NORMAL_MAX_CAPACITY="$MAX_CAP"
export SEARCH_ASG="$(json_get search <<<"$ASGS_JSON")"
export LISTING_ASG="$(json_get listing <<<"$ASGS_JSON")"
export BOOKING_ASG="$(json_get booking <<<"$ASGS_JSON")"
export MONOLITH_ASG="$(json_get monolith <<<"$ASGS_JSON")"
ENV
ok "wrote results/deploy/latest.json and results/deploy/env.sh"

DASH="$(tf output -raw cloudwatch_dashboard_name)"
cat <<DONE

============================================================
 Deployed.  Live URL (deliverable #1, screenshot it):
   $BASE_URL/search?city=Goa&limit=5
 CloudWatch dashboard:
   https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASH}
 Load the experiment variables in any new terminal:
   source results/deploy/env.sh
 Billing is running now. When done for the day:
   cd infra/terraform && CONFIRM_DESTROY=YES ../../scripts/teardown.sh
============================================================
DONE

if (( fail )); then
  die "Infrastructure is up but one or more smoke tests failed (see WARN lines above)."
fi
