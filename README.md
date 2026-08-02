# Enterprise SOC-in-a-Box (AWS Free Tier + k3s Lab Edition)

A serverless SIEM built on AWS Free Tier services, with Grafana self-hosted
on a k3s home lab. Ingests CloudTrail and VPC Flow Logs into a centralized
S3 data lake, runs detection queries via Athena, and (once Phase 3 lands)
automates incident response through Step Functions — all at ~$0.50/month.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design and the
reasoning behind each decision, and [COSTS.md](COSTS.md) for the running
cost breakdown.

## Status

- [x] **Phase 1 — Foundation**: VPC, CloudTrail, VPC Flow Logs, S3 data lake,
      Glue database, remote state, CI/CD pipeline
- [ ] **Phase 2 — Queries & Dashboard**: Glue Crawlers, Athena queries,
      Grafana on k3s
- [ ] **Phase 3 — Detection & Response**: Detection Lambdas, Step Functions
      incident response playbook
- [ ] **Phase 4 — Lab Simulation**: Traffic + threat simulators on k3s
- [ ] **Phase 5 — Documentation**: ADRs, final cost report, demo script,
      resume bullets

## Repo structure

```
enterprise-soc-in-a-box/
├── bootstrap/               # one-time: creates the Terraform remote-state bucket + lock table
├── terraform/
│   ├── modules/
│   │   ├── s3-data-lake/    # encrypted, partitioned S3 bucket + Glue database
│   │   ├── log-sources/     # VPC, CloudTrail, VPC Flow Logs
│   │   ├── athena-queries/  # (Phase 2)
│   │   ├── detection-rules/ # (Phase 3)
│   │   └── incident-response/ # (Phase 3)
│   └── environments/dev/    # wires the modules together for the dev environment
├── lambdas/                 # detection functions (Phase 3)
├── step-functions/          # incident response state machine (Phase 3)
├── grafana/                 # dashboards + datasource config (Phase 2)
├── simulators/               # traffic + threat generators for k3s (Phase 4)
├── queries/                 # Athena threat-hunting queries (Phase 2)
├── docs/
│   └── k3s-setup.md         # k3s cluster prerequisites for Phase 2/4
├── .github/workflows/       # Terraform CI/CD (validate/plan on PR, apply on merge)
├── ARCHITECTURE.md
├── COSTS.md
└── README.md
```

## Quickstart (Phase 1)

Prerequisites: an AWS account with Free Tier active, Terraform >= 1.6, AWS
CLI configured with credentials that can create IAM/S3/VPC/CloudTrail
resources.

### 1. Bootstrap remote state (one time only)

```bash
cd bootstrap
terraform init
terraform apply
```

Note the two outputs — you'll need them in the next step:

```bash
terraform output state_bucket_name
terraform output state_lock_table_name
```

Optional: also set `github_oidc_enabled = true` and `github_repo =
"yourname/enterprise-soc-in-a-box"` in a `bootstrap/terraform.tfvars` before
applying, if you want the CI/CD pipeline to be able to authenticate to AWS.
Then put the `github_actions_role_arn` output into a GitHub repo secret
named `AWS_GHA_ROLE_ARN`.

### 2. Configure the backend

Edit `terraform/environments/dev/backend.tf` and replace the two
`REPLACE_WITH_...` placeholders with the outputs from step 1.

### 3. Configure variables

```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — data_lake_bucket_name must be globally unique
```

### 4. Deploy

```bash
terraform init
terraform plan
terraform apply
```

This creates: the VPC (1 AZ, public + private subnet, no NAT Gateway), a
single-region CloudTrail trail, VPC Flow Logs published to S3, the S3 data
lake bucket (encrypted, lifecycle-managed), and a Glue Catalog database.

### 5. Verify

```bash
aws s3 ls s3://$(terraform output -raw data_lake_bucket)/ --recursive
```

Give CloudTrail a few minutes to deliver its first log file, and the VPC
Flow Logs a few minutes of network activity to have something to publish.

## What's next

Phase 2 adds Glue Crawlers to catalog the raw logs, a set of pre-built
Athena queries for threat hunting, and Grafana on your k3s cluster
(prerequisites in [docs/k3s-setup.md](docs/k3s-setup.md)) to visualize it
all.
