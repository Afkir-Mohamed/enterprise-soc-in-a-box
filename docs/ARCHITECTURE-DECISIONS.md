# Architecture Decision Records (ADRs)

Key design decisions made during the Enterprise SOC-in-a-Box project,
with the reasoning behind each. These are the questions you will be
asked in a technical interview.

---

## ADR-001: S3 + Athena over OpenSearch as the SIEM backend

**Decision:** Use S3 as the log store and Athena as the query engine
instead of a dedicated SIEM like OpenSearch Service or Splunk.

**Reasoning:**
- OpenSearch Service has no Free Tier — a minimal single-node cluster
  costs ~$15/month before ingesting a single log
- Athena is Free Tier eligible: 1 TB scanned/month at no cost
- The trade-off is real and documented: Athena is ad-hoc/batch, not
  sub-second/streaming. The Lambda detection layer compensates —
  logs are scanned within seconds of S3 delivery
- S3 + Athena is the pattern AWS itself uses for Amazon Security Lake

**In production:** Add OpenSearch for real-time correlation and keep
S3/Athena for long-term retention and threat hunting. The two are
complementary, not mutually exclusive.

---

## ADR-002: SSE-S3 over KMS for encryption at rest

**Decision:** Use SSE-S3 (AES-256, AWS-managed keys) instead of KMS
customer-managed keys.

**Reasoning:**
- KMS costs $1/month per key plus per-request charges
- SSE-S3 is free and provides strong encryption at rest
- No compliance mandate (PCI-DSS, HIPAA, FedRAMP) in this lab context

**In production:** KMS with customer-managed keys, automatic rotation,
and S3 Object Lock (WORM) for immutable log storage.

---

## ADR-003: VPC Flow Logs direct to S3, not CloudWatch Logs

**Decision:** Publish VPC Flow Logs directly to S3 in Parquet format.

**Reasoning:**
- CloudWatch Logs ingestion is billed at $0.57/GB
- S3 delivery is effectively free at this scale
- Parquet + per-hour partitioning means Athena queries flow logs with
  the same tooling as CloudTrail — no separate pipeline needed

---

## ADR-004: No NAT Gateway

**Decision:** The private subnet has no NAT Gateway and no outbound
internet route.

**Reasoning:**
- NAT Gateway costs $0.045/hour = ~$32/month — more than 10x the
  rest of this project's infrastructure cost combined
- Nothing in this lab requires outbound internet from the private
  subnet

**In production:** NAT Gateway for workloads that need outbound
internet, or VPC endpoints for AWS services to avoid NAT costs.

---

## ADR-005: Express over Standard Step Functions

**Decision:** Use Express Workflows for the incident response state
machine.

**Reasoning:**
- Express: 100,000 free state transitions/month vs 4,000 for Standard
- Express is also architecturally correct: short duration, high volume,
  event-driven. Standard workflows are for long-running, human-approval,
  exactly-once use cases
- Express at-least-once semantics is acceptable for alerting — a
  duplicate alert is better than a missed one

---

## ADR-006: Custom Lambda detection over GuardDuty

**Decision:** Build custom Lambda detection rules instead of GuardDuty
after its 30-day trial.

**Reasoning:**
- GuardDuty ~$1.50/month + Security Hub ~$2.10/month
- Lambda at this scale costs $0 (well within 1M free requests/month)
- Custom rules cover the same high-value patterns: root usage, mass
  IAM changes, unusual regions, CloudTrail tampering

**Trade-off documented:** GuardDuty has ML-based anomaly detection and
threat intelligence feeds that custom rules can't replicate. Interview
framing: "I know exactly which findings I'm trading away and why."

---

## ADR-007: Grafana on k3s over Amazon Managed Grafana

**Decision:** Self-host Grafana on a local k3s cluster.

**Reasoning:**
- Amazon Managed Grafana: $9+/user/month
- Self-hosted on k3s: $0
- Demonstrates hybrid cloud architecture: security dashboard on-prem
  querying a cloud data plane — a realistic enterprise pattern

---

## ADR-008: Root simulation deliberately omitted from threat simulator

**Decision:** The threat simulator does not simulate root account usage.

**Reasoning:**
- Using the actual root account is a real security event
- The detect-root-activity Lambda is verified through code review
- In production, root simulation is done in a dedicated sandbox account
  with break-glass procedures in place
- This decision demonstrates security judgment: knowing when NOT to
  run a test is as important as knowing how to run one
