# Architecture

## Overview

```
┌─────────────────────────────────────────────┐
│              AWS Free Tier                    │
│                                                │
│  [CloudTrail] ──────────────→ [S3 Data Lake]   │
│  [VPC Flow Logs] ──────────→    (encrypted,     │
│  [GuardDuty] ─── 30d trial ─→   partitioned)    │
│  [Security Hub] ─ 30d trial ─→                  │
│                                │                │
│  [EventBridge] ←────────── [S3 Event Notif.]    │
│       │                                        │
│  [Lambda (Detection Rules)]                     │
│       │                                        │
│  [Step Functions (Response)]                    │
│       │                                        │
│  [SNS → Slack / Email]                          │
└──────────────────┬─────────────────────────────┘
                   │
        Athena queries
                   │
┌──────────────────┴─────────────────────────────┐
│           Your k3s Lab (Home)                    │
│                                                  │
│  [Grafana (Helm)] ←───── [Athena Datasource]     │
│                                                  │
│  [Traffic Simulator] ─── AWS calls via boto3     │
│  [Threat Simulator] ─── simulated attacks        │
└──────────────────────────────────────────────────┘
```

## Phase 1 — what exists today

- **VPC** (`terraform/modules/log-sources`): one AZ, one public subnet, one
  private subnet, no NAT Gateway. A NAT Gateway costs ~$0.045/hour
  (~$32/month) — that alone would be 10x this whole project's budget, so
  it's deliberately absent. The private subnet has no outbound internet
  route; nothing in this lab needs it to.
- **CloudTrail** (`terraform/modules/log-sources`): a single-region trail,
  management events only. This is the Free Tier trail (one per region, no
  charge). Data events (S3 object-level, Lambda invocations) are a paid
  add-on and out of scope.
- **VPC Flow Logs** (`terraform/modules/log-sources`): published directly to
  S3 in Parquet format with per-hour partitioning — not routed through
  CloudWatch Logs, which has its own ingestion/storage costs past a small
  free allowance.
- **S3 Data Lake** (`terraform/modules/s3-data-lake`): one bucket, two
  prefixes (`cloudtrail/`, `vpc-flow-logs/`), SSE-S3 encryption, versioning,
  a lifecycle rule to Glacier at 90 days, and a Glue Catalog database ready
  for the crawlers that come in Phase 2.
- **Remote state** (`bootstrap/`): a separate, one-time local-state config
  that creates the S3 bucket + DynamoDB table the *real* Terraform config
  uses as its backend — solves the "state needs a backend before the
  backend exists" chicken-and-egg problem.
- **CI/CD** (`.github/workflows/terraform.yml`): validate + plan on every
  PR, apply on merge to `main`, authenticated via GitHub OIDC (no static AWS
  keys in GitHub secrets).

## Key design decisions (interview talking points)

**S3 + Athena over Elasticsearch/OpenSearch.**
Athena is Free Tier eligible (1 TB scanned/month). OpenSearch Service has no
free tier — even a minimal cluster runs ~$15/month before you've ingested a
single log. The trade-off is real (Athena is ad-hoc/batch, not
sub-second/real-time), and that trade-off *is* the talking point: knowing
when ad-hoc analytics is good enough versus when you need a always-on
search cluster is exactly the judgment call a cost-conscious architecture
review requires.

**SSE-S3 over KMS.**
KMS costs $1/month per customer-managed key plus per-10k-request charges.
SSE-S3 (AES-256, AWS-managed keys) is free and gives you encryption at
rest. For a lab project with no compliance mandate, that's the pragmatic
choice — documented here so the obvious follow-up question ("what would you
do differently in production?") has a ready answer: KMS + S3 Object Lock
for compliance-grade, audited, immutable storage.

**VPC Flow Logs to S3, not CloudWatch Logs.**
CloudWatch Logs ingestion is billed per GB past a small free tier, and
storage adds up over time. S3 delivery is free (aside from the ~$0.50/month
in S3 PUT requests at this scale) and Athena queries S3 directly — no need
to also pay to duplicate the data into CloudWatch.

**Express Step Functions over Standard (Phase 3).**
100,000 free state transitions/month vs. 4,000 for Standard workflows.
Express is also the *architecturally correct* choice for high-volume,
short-duration event processing like security response — this isn't just a
cost hack, it's the right tool for the job that also happens to be free at
this scale.

**GuardDuty/Security Hub as 30-day trials, replaced by custom Lambda
(Phase 3).**
After the trial, GuardDuty runs ~$1.50/account/month and Security Hub
~$2.10/account/month. A Lambda function watching CloudTrail events for the
same patterns (root activity, mass IAM changes, unusual regions) costs $0.
The interview framing: *"I designed a detection layer that covers the same
ground as GuardDuty for common patterns, at zero ongoing cost — and I know
exactly which findings I'm trading away by not paying for the managed
service."*

**Grafana on k3s, not Amazon Managed Grafana or EC2.**
Amazon Managed Grafana runs $9+/user/month (workspace + user licensing).
Self-hosting on EC2 would need an always-on instance. Both are unnecessary
when there's already a k3s cluster at home — `helm install` is simpler and
free, and it doubles as a hybrid-cloud talking point: a security dashboard
running on-prem, querying a cloud data plane.

## What's next

- **Phase 2**: Glue Crawlers, Athena queries (`queries/`), Grafana on k3s
  (`grafana/`)
- **Phase 3**: Detection Lambdas (`lambdas/`), Step Functions incident
  response (`step-functions/`)
- **Phase 4**: Traffic + threat simulators on k3s (`simulators/`)
- **Phase 5**: Full docs pass, ADRs, cost report, demo script
