# Enterprise SOC-in-a-Box (AWS Free Tier + k3s Lab Edition)

A serverless SIEM built on AWS Free Tier services, with Grafana self-hosted
on a k3s home lab. Ingests CloudTrail and VPC Flow Logs into a centralized
S3 data lake, runs detection queries via Athena, automates incident response
through Step Functions, and visualizes everything in Grafana — all at
~$0.50/month.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design and the reasoning
behind each decision, [COSTS.md](COSTS.md) for the running cost breakdown,
and [docs/ARCHITECTURE-DECISIONS.md](docs/ARCHITECTURE-DECISIONS.md) for the
8 ADRs that explain every trade-off.

---

## Status — All Phases Complete ✅

- [x] **Phase 1 — Foundation**: VPC, CloudTrail, VPC Flow Logs, S3 data lake,
      Glue database, remote state, CI/CD pipeline
- [x] **Phase 2 — Queries & Dashboard**: Glue Crawlers, 11 Athena threat-hunting
      queries (MITRE ATT&CK mapped), Grafana on k3s with 4 live dashboards
- [x] **Phase 3 — Detection & Response**: 3 detection Lambdas (root usage, mass
      IAM changes, unusual regions), Step Functions EXPRESS incident response
      playbook, EventBridge pipeline, SNS alerts
- [x] **Phase 4 — Lab Simulation**: Traffic generator CronJob + threat simulator
      on k3s — 3 attack scenarios verified end-to-end
- [x] **Phase 5 — Documentation**: 8 ADRs, demo script, teardown guide,
      resume bullets

---

## Architecture

```
CloudTrail ──────────────────────────────→ S3 Data Lake
VPC Flow Logs (Parquet) ─────────────────→ (encrypted, partitioned,
                                            lifecycle → Glacier 90d)
                                                  │
                              ┌───────────────────┤
                              │                   │
                    EventBridge (S3 PutObject)   Athena
                              │                   │
              ┌───────────────┼───────────────┐   └──→ Grafana (k3s)
              ↓               ↓               ↓
       detect-root    detect-mass-iam  detect-network-recon
       (Lambda)         (Lambda)          (Lambda)
              └───────────────┼───────────────┘
                              ↓
                    Step Functions EXPRESS
                    ┌─────────────────────┐
                    │ Notify (SNS)        │
                    │ Route by severity   │
                    │ Contain (HIGH only) │
                    │ Document to S3      │
                    └─────────────────────┘
```

**Cost:** ~$0.50/month (VPC Flow Log delivery only — everything else Free Tier)
**Detection latency:** <10 minutes (CloudTrail delivery window)

---

## Repo Structure

```
enterprise-soc-in-a-box/
├── bootstrap/                    # one-time: Terraform remote-state bucket + DynamoDB lock
├── terraform/
│   ├── modules/
│   │   ├── s3-data-lake/         # encrypted S3 bucket + Glue database
│   │   ├── log-sources/          # VPC, CloudTrail, VPC Flow Logs
│   │   ├── athena-queries/       # Glue crawlers, Athena workgroup, results bucket
│   │   └── detection-rules/      # Lambdas, EventBridge, Step Functions, SNS
│   └── environments/dev/         # wires all modules together
├── lambdas/
│   ├── detect-root-activity/     # HIGH: any root API call
│   ├── detect-mass-iam/          # HIGH: 5+ IAM writes in one log file
│   └── detect-network-recon/     # MEDIUM: API calls outside allowed regions
├── step-functions/
│   └── incident-response.asl.json
├── queries/
│   ├── iam/detections.sql        # root usage, no-MFA login, mass IAM, new access keys
│   ├── network/detections.sql    # unusual regions, SG changes, CloudTrail tampering
│   └── account/detections.sql   # brute force, S3 exposure, secrets access, daily rollup
├── simulators/
│   ├── traffic-generator/        # k3s CronJob: baseline AWS API activity every 30 min
│   ├── threat-simulator/         # k3s Job: mass IAM, unusual region, CloudTrail recon
│   └── setup.sh                  # one-time k8s namespace + secret + configmap setup
├── grafana/                      # dashboard JSON + datasource config
├── docs/
│   ├── ARCHITECTURE-DECISIONS.md # 8 ADRs with full reasoning
│   ├── DEMO-SCRIPT.md            # interview walkthrough guide
│   ├── RESUME-BULLETS.md         # CV bullets, LinkedIn write-up, interview Q&A
│   ├── TEARDOWN.md               # complete AWS teardown instructions
│   └── k3s-setup.md              # k3s cluster prerequisites
├── .github/workflows/
│   └── terraform.yml             # validate+plan on PR, apply on merge (OIDC auth)
├── ARCHITECTURE.md
├── COSTS.md
└── README.md
```

---

## Quickstart

### Prerequisites
- AWS account with Free Tier active
- Terraform >= 1.6
- AWS CLI configured
- kubectl + Helm (for Grafana/simulators)

### 1. Bootstrap remote state (one time only)

```bash
cd bootstrap
terraform init
terraform apply
```

Note the outputs — you need them in step 2:
```bash
terraform output state_bucket_name
terraform output state_lock_table_name
```

### 2. Configure the backend

Edit `terraform/environments/dev/backend.tf` and replace the two
`REPLACE_WITH_...` placeholders with the outputs from step 1.

### 3. Configure variables

```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars:
#   data_lake_bucket_name        = "soc-in-a-box-<your-account-id>-dev"
#   athena_results_bucket_name   = "soc-in-a-box-athena-<your-account-id>-dev"
#   alert_email                  = "you@example.com"  # optional
```

### 4. Deploy everything

```bash
terraform init
terraform apply
```

Deploys all 4 Terraform modules in one apply: VPC + log sources, S3 data
lake, Athena workgroup + Glue crawlers, detection Lambdas + Step Functions.

### 5. Register the CloudTrail Athena table

```bash
aws glue create-table \
  --database-name soc_in_a_box \
  --table-input file://docs/cloudtrail-table.json
```

Then add today's partition:
```bash
aws athena start-query-execution \
  --query-string "ALTER TABLE cloudtrail_logs ADD IF NOT EXISTS
    PARTITION (year='$(date +%Y)', month='$(date +%m)', day='$(date +%d)')
    LOCATION 's3://<your-bucket>/cloudtrail/AWSLogs/<account-id>/CloudTrail/eu-central-1/$(date +%Y/%m/%d)/'" \
  --query-execution-context Database=soc_in_a_box \
  --work-group soc-in-a-box
```

### 6. Deploy Grafana on k3s

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
kubectl create namespace monitoring
helm install grafana grafana/grafana \
  --namespace monitoring \
  --set adminPassword='YourPassword' \
  --set service.type=NodePort \
  --set service.nodePort=32000

# Install Athena plugin
kubectl exec -n monitoring deploy/grafana -- \
  grafana-cli plugins install grafana-athena-datasource
kubectl rollout restart deployment grafana -n monitoring
```

Open `http://<node-ip>:32000` and add Amazon Athena as a datasource.

### 7. Set up and run the simulators

```bash
cd ~/enterprise-soc-in-a-box
bash simulators/setup.sh

# Run the threat simulator to test the full pipeline
kubectl apply -f simulators/threat-simulator/job.yaml -n soc-simulators
kubectl logs -f job/threat-simulator -n soc-simulators
```

Wait 10-15 minutes, then check CloudWatch Logs for Lambda executions.

---

## Detection Coverage (MITRE ATT&CK)

| Detection | Severity | MITRE | Lambda |
|---|---|---|---|
| Root account usage | HIGH | T1078.004 | detect-root-activity |
| Mass IAM changes | HIGH | T1136.003, T1098 | detect-mass-iam |
| Unusual region API calls | MEDIUM | T1535 | detect-network-recon |
| Console login without MFA | MEDIUM | T1078 | Athena query |
| CloudTrail tampering | HIGH | T1562.008 | Athena query |
| S3 bucket made public | HIGH | T1530 | Athena query |
| Brute force / AccessDenied spike | MEDIUM | T1110 | Athena query |
| New access key created | MEDIUM | T1098.001 | Athena query |

---

## Cost Breakdown

| Service | Monthly Cost |
|---|---|
| VPC Flow Logs → S3 | ~$0.50 |
| CloudTrail (1 trail) | $0 (Free Tier) |
| S3 storage | $0 (Free Tier) |
| Lambda | $0 (Free Tier) |
| Athena | $0 (Free Tier) |
| Step Functions EXPRESS | $0 (Free Tier) |
| EventBridge | $0 (Free Tier) |
| Grafana (k3s) | $0 (self-hosted) |
| **Total** | **~$0.50/month** |

Equivalent managed stack (OpenSearch + GuardDuty + Security Hub +
Managed Grafana) would cost $25-40/month minimum.

---

## Teardown

```bash
cd terraform/environments/dev && terraform destroy -auto-approve
```

Full instructions in [docs/TEARDOWN.md](docs/TEARDOWN.md).
