# Contributing to the Airbnb SOA PoC

## Team ownership

- **Kalp Shah — cloud infrastructure:** Terraform networking, ALB path routing, target groups, ASGs, scaling policies, CloudWatch and teardown. Primary experiment: E2.
- **Vansh Vora — services/backend:** search, listing and booking APIs, monolith comparison, data model, Redis, SQS worker and idempotency. Primary experiments: E3 and E5.
- **Meet Gandhi — load testing/analysis:** k6 workloads, E1/E2/E3 test execution support, CloudWatch collection, plots and cost model. Primary experiments: E1, E4 and E6.

Ownership is a starting point, not a restriction. Everyone should review the architecture and be able to explain every experiment in the viva.

## First-time setup on each laptop

Install Git, Docker Desktop, and the tools needed for the workstream (Terraform, AWS CLI, k6 and Python as applicable). Each member should use their own GitHub account and a verified email address.

Configure the local Git identity once:

```bash
git config --global user.name "YOUR REAL NAME"
git config --global user.email "YOUR VERIFIED GITHUB EMAIL"
```

Clone the shared repository separately on each laptop:

```bash
git clone https://github.com/OWNER/airbnb-soa-poc.git
cd airbnb-soa-poc
git switch main
git pull --ff-only origin main
```

Do not share passwords, personal access tokens or SSH private keys. Add each teammate as a repository collaborator through GitHub's repository settings.

## Branch and pull-request workflow

1. Start from an up-to-date `main` branch.
2. Create a branch named for one focused task, e.g. `feat/search-cpu-workload`, `feat/alb-path-routing` or `test/e1-fixed-capacity`.
3. Make and test the change on your own laptop.
4. Commit only the files related to that change, with a message describing what changed.
5. Push the branch and open a pull request (PR).
6. Ask at least one teammate to review it. Merge only after the reviewer can run or inspect the change.
7. Delete the feature branch after merging, then pull `main` before starting the next task.

Example:

```bash
git switch main
git pull --ff-only origin main
git switch -c feat/search-cpu-workload
# edit and test the implementation
git status
git add services/search tests
git commit -m "Add bounded CPU workload to search endpoint"
git push -u origin feat/search-cpu-workload
```

Use a real commit for a real change. Do not create empty commits, copy the same change into several commits, change system clocks, or set `GIT_AUTHOR_DATE` / `GIT_COMMITTER_DATE` to manufacture earlier timestamps. GitHub records the commit metadata; it does not prove who physically typed the code or when all prior design work happened.

## Before merging

- Run the relevant unit/integration tests.
- Keep `.env`, AWS credentials, key pairs, Terraform state and other secrets out of Git.
- Update the README when commands, routes, environment variables or infrastructure outputs change.
- Include a short PR description: purpose, files changed, tests run, and evidence (logs/screenshots where useful).
- Record measured results in `results/` only after the experiment actually ran. Do not invent or pre-fill performance results.

## Commit messages

Prefer imperative, specific messages, for example:

- `Add ALB listener rules for service path routing`
- `Add idempotency handling to booking endpoint`
- `Add k6 fixed-capacity workload for E1`
- `Export CloudWatch metrics to experiment CSV`
