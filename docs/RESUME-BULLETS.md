# Resume / CV Write-Up

---

## Project Title (for CV)

**Enterprise SOC-in-a-Box** | AWS Free Tier · Terraform · Python · k3s
*Personal Project — 2026*

---

## One-Line Summary

Built a serverless SIEM on AWS Free Tier that ingests CloudTrail and
VPC Flow Logs, runs automated threat detection via Lambda, and
triggers an incident response playbook through Step Functions —
at ~$0.50/month.

---

## CV Bullets (XYZ format — Achievement + Action + Result)

Pick 3-4 of these depending on the role:

**For Cloud Security / Security Engineer roles:**
- Designed and deployed a serverless SIEM on AWS Free Tier using
  CloudTrail, S3, Athena, and Lambda, achieving detection latency
  under 10 minutes at ~$0.50/month operating cost
- Built three automated detection rules (root usage, mass IAM changes,
  unusual regions) triggering Step Functions incident response playbooks
  that notify, enrich with Athena queries, and document findings to S3
- Authored 11 threat-hunting SQL queries mapped to MITRE ATT&CK
  techniques (T1078, T1110, T1136, T1530, T1562) for IAM, network,
  and account-level detection

**For Cloud Engineer / DevOps roles:**
- Architected a modular Terraform IaC project (4 modules, remote state
  with S3 + DynamoDB locking, GitHub Actions CI/CD via OIDC) deploying
  25+ AWS resources across VPC, S3, Glue, Athena, Lambda, and
  Step Functions
- Deployed Grafana on a self-hosted k3s cluster (WSL2) connected to
  AWS Athena as a datasource, demonstrating hybrid cloud observability
  with 4 live security dashboards
- Reduced infrastructure cost by 98% vs equivalent managed services
  (OpenSearch + GuardDuty + Managed Grafana) through deliberate
  Free Tier architecture decisions documented in 8 ADRs

**For SOC Analyst / Detection Engineering roles:**
- Developed a threat simulator running on Kubernetes generating 3
  attack scenarios (mass IAM changes, unusual region API calls,
  CloudTrail recon) to validate detection pipeline end-to-end
- Implemented EventBridge → Lambda detection pipeline processing
  CloudTrail log files within seconds of S3 delivery, with findings
  routed through Step Functions Express Workflows for automated
  triage
- Demonstrated zero false positives on baseline traffic and correct
  detection on all 3 simulated attack scenarios in live testing

---

## GitHub README Project Description

Paste this at the top of your GitHub repo:

```
# Enterprise SOC-in-a-Box

A production-grade serverless SIEM built entirely on AWS Free Tier,
costing ~$0.50/month to operate.

Ingests CloudTrail and VPC Flow Logs into a centralized S3 data lake,
runs real-time threat detection via Lambda (root usage, mass IAM changes,
unusual regions), and triggers automated incident response through Step
Functions — with Grafana dashboards self-hosted on k3s.

Stack: Terraform · AWS (CloudTrail, S3, Athena, Glue, Lambda,
EventBridge, Step Functions, SNS) · Python · Kubernetes (k3s) · Grafana

Cost: ~$0.50/month (VPC Flow Log delivery only — everything else is
Free Tier)

Detection latency: <10 minutes (CloudTrail delivery window)
```

---

## LinkedIn Project Section

**Enterprise SOC-in-a-Box**
*Jan 2026 – Aug 2026*

Built a complete serverless security monitoring platform on AWS Free
Tier to demonstrate cloud security engineering depth for senior
Cloud/Security Engineer roles.

Designed and deployed: a modular Terraform IaC stack (VPC, CloudTrail,
VPC Flow Logs, S3 data lake, Glue catalog, Athena workgroup), three
automated detection Lambdas triggered by EventBridge on every CloudTrail
delivery, a Step Functions incident response playbook, and Grafana
dashboards on a self-hosted k3s cluster — all at ~$0.50/month.

Key decisions: S3+Athena over OpenSearch (cost), custom Lambda detection
over GuardDuty (transparency + cost), Express Step Functions over
Standard (volume + free tier), SSE-S3 over KMS (compliance trade-off
documented). All 8 architectural trade-offs documented as ADRs.

Skills: AWS Security · Terraform · Python · Kubernetes · Grafana ·
CloudTrail · Athena · Step Functions · EventBridge · MITRE ATT&CK

---

## Interview Talking Points Cheat Sheet

| Question | Answer |
|---|---|
| Why this project? | "Proves I can architect for security AND cost — two things that are usually in tension" |
| Cost breakdown? | "$0.50/month — VPC Flow Log delivery. Everything else Free Tier. OpenSearch equivalent would be $15+/month" |
| Detection latency? | "<10 min — CloudTrail delivery window. Acceptable for IAM/API threats, would need streaming for network threats" |
| Why not GuardDuty? | "$1.50/month + black box. Custom rules = $0 + I know exactly what I detect and what I don't" |
| What would you add in prod? | "KMS + Object Lock, OpenSearch for hot data, multi-region trail, PR-gated Terraform apply" |
| Biggest challenge? | "Glue Crawler + CloudTrail's nested AWSLogs partition structure — solved by manually defining the Glue table with the CloudTrail SerDe" |
| MITRE coverage? | "T1078 (valid accounts/root), T1110 (brute force), T1136 (create account), T1530 (S3 exposure), T1562 (impair defenses/CloudTrail tampering)" |
