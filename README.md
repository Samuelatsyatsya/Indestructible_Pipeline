# Indestructible Pipeline — FinCorp DevSecOps Lab

**Author:** Samuel Atsyatsya
**Date:** 22 June 2026
**AWS Account:** 309797288544
**Primary Region:** eu-central-1 (Frankfurt)
**DR Region:** eu-west-1 (Ireland)

---

## Overview

This lab demonstrates two production-grade DevSecOps capabilities for FinCorp:

1. **Secure CI/CD Pipeline** — A Jenkins pipeline that builds Docker images, scans them with Trivy, blocks any image with HIGH or CRITICAL vulnerabilities, and pushes only clean images to an immutable ECR registry before deploying to EC2.

2. **Cross-Region Disaster Recovery** — AWS Backup continuously replicates RDS snapshots from Frankfurt to Ireland. A scripted DR simulation deletes the primary database (region failure), then restores from the Ireland vault and confirms availability.

---

## Architecture

```
Developer Push (GitHub dev branch)
        │
        ▼
   Jenkins Pipeline
   ┌─────────────────────────────────────────────────────┐
   │  Checkout → Build Images → Trivy Scan → Push → Deploy│
   │                               │                      │
   │                         BLOCKS on HIGH/CRITICAL      │
   └─────────────────────────────────────────────────────┘
        │ (clean images only)
        ▼
   ECR (IMMUTABLE tags)                    EC2 App Server
   ├── fincorp/loan-api:<build>-<sha>  →   ├── fincorp-api  (Node.js/Express)
   └── fincorp/loan-ui:<build>-<sha>   →   └── fincorp-ui   (React + nginx)

   RDS PostgreSQL (eu-central-1)
        │  AWS Backup daily + on-demand
        ▼
   DR Vault (eu-west-1)  ──restore──▶  fincorp-restored-db (eu-west-1)
```

---

## Application

A **Loan Calculator** with a React/Tailwind frontend and a Node.js/Express backend.

- **Frontend:** React + Tailwind CSS, served by nginx inside Docker. nginx proxies `/api/` calls to the backend container — the browser never talks to port 3001 directly.
- **Backend:** Express REST API with a `POST /api/calculate` endpoint that computes monthly payment, total interest, and amortization schedule. Secured with `helmet` and `cors`.
- **Local dev:** `docker compose up` from repo root starts both services.

**Live URL:** `http://63.183.200.179`

---

## Infrastructure (Terraform)

All infrastructure is managed with Terraform using a modular structure and local state. The AWS profile `CostDetective` is used throughout.

| Module | Resource | Details |
|---|---|---|
| `vpc` | VPC + subnets | 10.0.0.0/16, 2 public + 2 private subnets in eu-central-1 |
| `ecr` | ECR repositories | `fincorp/loan-api`, `fincorp/loan-ui` — **IMMUTABLE** tags |
| `codeartifact` | npm proxy | `fincorp` domain, `fincorp-npm` repository — all Docker `npm install`s route through it |
| `secrets` | Secrets Manager | RDS master credentials at `fincorp/rds/master-password` |
| `rds` | PostgreSQL 15.18 | `db.t3.micro`, encrypted, private subnets, no public access |
| `backup` | AWS Backup | Daily at 02:00 UTC + cross-region copy to eu-west-1 |
| `ec2` | App server | AL2023, Docker + Compose, IAM role for ECR pull |

### Secrets Management

RDS credentials are stored in AWS Secrets Manager and **never appear** in `.tfvars`, environment variables, or code. Terraform reads the secret via a `data` source, with the `secret_version_arn` output used to enforce dependency ordering between the secrets module and the RDS module.

### Deploy

```bash
cd infra
terraform init
terraform plan -var="db_password=<password>"
terraform apply -var="db_password=<password>"
```

> **Cost estimate:** ~$65–80/month if left running 24/7. Run `terraform destroy` after the lab.

---

## CI/CD Pipeline (Jenkins)

**Job:** `indestructible-pipeline`
**Trigger:** Webhook on push to `dev` branch
**Image tag format:** `<build_number>-<git_sha_7>`

### Pipeline Stages

```
Checkout
    │
   CodeArtifact Login  (short-lived npm token → /tmp/ca-token.txt)
    │
    ├── Build Backend ──┐
    │                   ├── (parallel, npm installs via CodeArtifact)
    └── Build Frontend ─┘
            │
    ├── Scan Backend  ──┐
    │                   ├── (parallel Trivy)  ← GATE: blocks on HIGH/CRITICAL
    └── Scan Frontend ──┘
            │
        Push to ECR  (immutable tag)
            │
        Deploy to EC2  (scp compose file → docker compose up -d)
```

### Security Gate — Trivy

```bash
trivy image \
  --exit-code 1 \
  --severity HIGH,CRITICAL \
  --ignorefile .trivyignore \
  --no-progress \
  --format table \
  <image>
```

`--exit-code 1` causes the pipeline to **fail and stop** if any HIGH or CRITICAL CVE is found. The image never reaches ECR.

**Accepted exceptions (`.trivyignore`):** 11 CVEs in npm's internal bundled packages (`cross-spawn`, `glob`, `minimatch`, `tar`). These are build-time tools only — they are not present or reachable in the running container. Each is documented in `.trivyignore`.

**OS patching:** All Dockerfile stages run `RUN apk upgrade --no-cache` to pull the latest Alpine package versions at build time, eliminating known OS-level CVEs.

### Immutable ECR Tags

ECR repositories are configured with `image_tag_mutability = "IMMUTABLE"`. Attempting to push a second image to an existing tag fails with:

```
tag invalid: The image tag '3-f365834' already exists in the 'fincorp/loan-api' repository
  and cannot be overwritten because the repository is immutable.
```

This guarantees that every tag in ECR is a permanent, unmodifiable artifact — what was scanned is exactly what runs in production.

### ECR Repositories

| Repository | Mutability | URI |
|---|---|---|
| `fincorp/loan-api` | IMMUTABLE | `309797288544.dkr.ecr.eu-central-1.amazonaws.com/fincorp/loan-api` |
| `fincorp/loan-ui` | IMMUTABLE | `309797288544.dkr.ecr.eu-central-1.amazonaws.com/fincorp/loan-ui` |

### Image History (loan-ui)

| Tag | Pushed |
|---|---|
| `3-f365834` | 2026-06-22 11:59 UTC |
| `5-e5b4a22` | 2026-06-22 12:29 UTC |
| `6-e5b4a22` | 2026-06-22 12:42 UTC |
| `7-832a317` | 2026-06-22 13:31 UTC |
| `12-31136b6` | 2026-06-22 13:53 UTC |
| `15-5e73b7e` | 2026-06-22 14:27 UTC |

> Builds #1 and #2 were intentionally blocked by Trivy — no ECR entry exists for those build numbers, proving the gate works.

---

## Disaster Recovery

### Strategy

AWS Backup runs a daily backup plan against the primary RDS instance in eu-central-1. Every backup is automatically copied to a vault in eu-west-1 using a `copy_action` in the backup plan. Both vaults retain recovery points for 30 days.

### Vaults

| Vault | Region | Recovery Points |
|---|---|---|
| `fincorp-primary-vault` | eu-central-1 | — |
| `fincorp-dr-vault` | eu-west-1 | 1 |

### DR Scripts

Two scripts in `scripts/` orchestrate the full DR cycle:

**`scripts/dr-backup.sh`** — triggers an on-demand backup of the primary RDS, waits for completion, copies it cross-region to the DR vault, and prints the DR recovery point ARN.

**`scripts/dr-restore.sh <DR_RECOVERY_POINT_ARN>`** — simulates a region failure by deleting the primary RDS, then starts a restore job in eu-west-1 and polls until the restored database is available.

Both scripts use structured logging (`[INFO]`, `[OK]`, `[WARN]`, `[ERROR]`) with UTC timestamps to stderr, and print only the actionable output (the recovery ARN) to stdout so the scripts can be piped together.

### Automatic Failover Flow

When the primary RDS goes down, the following happens automatically — no engineer intervention needed:

```
fincorp-primary-db goes down
         │
         ▼  (2 minutes)
CloudWatch Alarm: DatabaseConnections ≤ 0
         │
         ▼
SNS Topic: fincorp-dr-alerts
         │
    ┌────┴────┐
    ▼         ▼
Lambda      Email → you
    │
    ├── Finds latest recovery point in fincorp-dr-vault (eu-west-1)
    ├── Calls start_restore_job → fincorp-restored-db
    ├── Polls until status = available
    └── Updates Route 53 CNAME:
        primary.db.fincorp.internal → restored endpoint
         │
         ▼
App reconnects automatically on next DB call
         │
         ▼
Email: "DR COMPLETE — app live in eu-west-1"
```

**Components provisioned:**

| Component | Resource | Purpose |
|---|---|---|
| CloudWatch Alarm | `fincorp-rds-primary-down` | Fires after 2 consecutive minutes of zero DB connections |
| SNS Topic | `fincorp-dr-alerts` | Fans out to Lambda (trigger) and email (notification) |
| Lambda | `fincorp-dr-failover` | Restores DB in eu-west-1 and updates Route 53 |
| Route 53 | `primary.db.fincorp.internal` | DNS abstraction — app never hardcodes an RDS endpoint |

### DR Simulation — 22 June 2026

**Step 1: On-demand backup triggered**
```bash
./scripts/dr-backup.sh
```
Backup completed in eu-central-1. Cross-region copy confirmed in `fincorp-dr-vault` (eu-west-1).

**Step 2: Region failure simulated**
Primary RDS `fincorp-primary-db` (eu-central-1) deleted.

**Step 3: Restore initiated**
```bash
./scripts/dr-restore.sh "<DR_RECOVERY_POINT_ARN>"
```

**Step 4: Restore confirmed available**

| Property | Value |
|---|---|
| Instance ID | `fincorp-restored-db` |
| Region | eu-west-1 |
| Engine | PostgreSQL 15.18 |
| Class | db.t3.micro |
| Storage | 20 GB (encrypted) |
| Status | **available** |
| Endpoint | `fincorp-restored-db.cr8q6wmscu1l.eu-west-1.rds.amazonaws.com` |

---

## Jenkins Credentials Required

| Credential ID | Type | Purpose |
|---|---|---|
| `indestructible-creds` | AWS access key | ECR login/push **and** CodeArtifact auth token |
| `indestructible-ssh` | SSH private key | SSH/SCP into EC2 |
| `indestructible-ec2` | Secret text | EC2 public IP address |

The `CodeArtifact Login` stage needs the IAM principal behind `indestructible-creds` to fetch a token and read packages. This is **codified in the `codeartifact` Terraform module** — it creates the managed policy `fincorp-codeartifact-ci-pull` (scoped to the `fincorp` domain and `fincorp-npm` repo) and attaches it to the CI user:

```hcl
codeartifact:GetAuthorizationToken   → on the fincorp domain ARN
codeartifact:GetRepositoryEndpoint   → on the fincorp-npm repo ARN
codeartifact:ReadFromRepository      → on the fincorp-npm repo ARN
sts:GetServiceBearerToken            → fenced to codeartifact.amazonaws.com
```

The attachment target defaults to the `CostDetective` user and is overridable via the module's `ci_principal_name` variable (set it if you split out a dedicated Jenkins IAM user).

---

## Repository Structure

```
Indestructible_Pipeline/
├── backend/
│   ├── src/index.js          # Express API — /api/calculate, /health
│   ├── package.json
│   └── Dockerfile            # Multi-stage, non-root user, apk upgrade
├── frontend/
│   ├── src/App.jsx           # React loan calculator UI
│   ├── nginx.conf            # nginx reverse proxy for /api/ → backend
│   ├── package.json
│   └── Dockerfile            # Multi-stage, nginx:alpine, apk upgrade
├── infra/
│   ├── main.tf               # Root module — wires all modules together
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       ├── vpc/
│       ├── ecr/
│       ├── codeartifact/
│       ├── secrets/
│       ├── rds/
│       ├── backup/
│       └── ec2/
├── scripts/
│   ├── dr-backup.sh          # On-demand backup + cross-region copy
│   └── dr-restore.sh         # Simulate failure + restore in eu-west-1
├── docker-compose.yml        # Local development
├── Jenkinsfile               # Declarative pipeline
├── .trivyignore              # Accepted CVE exceptions with justification
└── .gitignore                # Excludes tfstate, tfvars, node_modules, keys
```

---

## Security Controls Summary

| Control | Implementation |
|---|---|
| Vulnerability scanning | Trivy on every build, blocks HIGH/CRITICAL |
| Immutable artifacts | ECR `IMMUTABLE` tag mutability |
| Secret management | AWS Secrets Manager — no plaintext credentials anywhere |
| Non-root containers | Backend runs as `fincorp` user (UID 1001) |
| OS patching | `apk upgrade --no-cache` in every Dockerfile stage |
| No long-lived Docker credentials | ECR token refreshed per build (12h TTL) |
| Backend not publicly exposed | Only nginx on port 80 is public; port 3001 is internal only |
| Encrypted database | RDS `storage_encrypted = true` |
| Private RDS | Database in private subnets, no public access |
