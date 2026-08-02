# Cost Breakdown

## Phase 1 (what's deployed today)

| Resource | Free Tier | This Project's Usage | Monthly Cost |
|---|---|---|---|
| CloudTrail (management events trail) | 1 trail/region — free | 1 trail | $0 |
| VPC (subnets, IGW, route tables) | Always free | 1 VPC, no NAT | $0 |
| VPC Flow Logs → S3 | No free tier, billed on ingestion | ~5 GB/month at lab scale | ~$0.50 |
| S3 (data lake bucket) | 5 GB standard storage | ~200 MB logs + metadata | $0 |
| S3 (Terraform state bucket) | 5 GB standard storage | Kilobytes | $0 |
| DynamoDB (state lock table) | 25 GB + on-demand free tier | A few requests/apply | $0 |
| Glue Catalog database | Always free (crawlers billed separately, Phase 2) | 1 database, 0 tables yet | $0 |
| **Phase 1 total** | | | **~$0.50/month** |

## Full-project projection (once all phases are built)

| Service | Free Tier | Estimated Usage | Cost |
|---|---|---|---|
| CloudTrail | 1 trail free | 1 trail | $0 |
| VPC Flow Logs | None | ~5 GB → S3 | ~$0.50 |
| S3 | 5 GB standard | ~200 MB | $0 |
| Lambda | 1M requests / 400k GB-s | ~50k requests | $0 |
| Athena | 1 TB scanned | ~10 GB scanned | $0 |
| Step Functions Express | 100k transitions | ~5k transitions | $0 |
| SQS | 1M requests | ~10k requests | $0 |
| SNS | 1M publishes | ~100 publishes | $0 |
| EventBridge | 100M custom events | ~10k events | $0 |
| GuardDuty | 30-day trial | then ~$1.50/month if kept on | $0 or $1.50 |
| Security Hub | 30-day trial | then ~$2.10/month if kept on | $0 or $2.10 |
| AWS Config | 10k config items + 2 rules free | Within limits | $0 |
| Grafana (k3s) | N/A — your hardware | — | $0 |
| **Total, GuardDuty/Security Hub disabled after trial** | | | **~$0.50/month** |
| **Total, GuardDuty/Security Hub kept on** | | | **~$4.10/month** |

The plan is to disable GuardDuty and Security Hub once their 30-day trials
end (the custom Lambda detection layer built in Phase 3 is designed to
cover the same detection patterns), keeping the steady-state cost near
$0.50/month indefinitely.

## Tracking actual spend

Once Phase 1 is deployed, check actual cost via AWS Cost Explorer or Billing
Console — this table will be updated with real numbers at the end of each
phase rather than left as estimates only.
