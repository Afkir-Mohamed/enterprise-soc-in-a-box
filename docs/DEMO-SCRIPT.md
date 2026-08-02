# Demo Script — Interview / Portfolio Walkthrough

Use this when showing the project live or walking an interviewer
through it. Total time: 10-15 minutes.

---

## Setup (5 minutes before the demo)

```bash
# 1. Deploy the stack
cd ~/enterprise-soc-in-a-box/terraform/environments/dev
terraform apply -auto-approve

# 2. Add CloudTrail table partitions for today
aws athena start-query-execution \
  --query-string "ALTER TABLE cloudtrail_logs ADD IF NOT EXISTS
    PARTITION (year='2026', month='08', day='$(date +%d)')
    LOCATION 's3://soc-in-a-box-627327986089-dev/cloudtrail/AWSLogs/627327986089/CloudTrail/eu-central-1/2026/08/$(date +%d)/'" \
  --query-execution-context Database=soc_in_a_box \
  --work-group soc-in-a-box

# 3. Run the threat simulator
kubectl apply -f simulators/threat-simulator/job.yaml -n soc-simulators
```

Wait 10-15 minutes for CloudTrail to deliver logs, then start the demo.

---

## The Walkthrough

### 1. Start with the problem (1 minute)

"Most SIEM solutions — Splunk, QRadar, even AWS Security Hub — cost
hundreds or thousands of dollars a month at enterprise scale. I wanted
to prove you can get 80% of the detection coverage for $0.50/month
using only AWS Free Tier services and a home lab."

### 2. Show the architecture (2 minutes)

Draw or point to ARCHITECTURE.md:

```
CloudTrail → S3 → EventBridge → Lambda (detection)
                                     ↓
                              Step Functions
                                     ↓
                            SNS alert + incident log
                                     ↓
                    Athena (threat hunting) → Grafana (k3s)
```

Key talking points:
- "Everything except the ~$0.50/month VPC Flow Log delivery is Free Tier"
- "The Lambda fires within seconds of CloudTrail delivering a log file
  — that's the detection latency"
- "Grafana runs on my local k3s cluster querying AWS Athena — hybrid
  cloud in practice, not just in theory"

### 3. Show Grafana live (2 minutes)

Open `http://<wsl-ip>:32000`

- Point to the Event Timeline panel: "This spike here is the threat
  simulator running — you can see the volume jump"
- Point to Top Identities: "In a real investigation, an unknown identity
  appearing here is your first flag"
- Point to Failed API Calls: "Zero here means no brute force attempts
  against this account today"

### 4. Run a threat hunting query (2 minutes)

In the AWS Console → Athena, or via CLI:

```sql
SELECT eventtime, eventname, eventsource,
       useridentity.arn, sourceipaddress
FROM cloudtrail_logs
WHERE year = '2026' AND month = '08'
  AND eventsource = 'iam.amazonaws.com'
  AND eventname IN ('CreateUser','AttachUserPolicy','CreateAccessKey')
ORDER BY eventtime DESC
LIMIT 10
```

"These are the IAM write operations the threat simulator generated.
In a real incident, this query tells me exactly what an attacker did
and in what order."

### 5. Show the Lambda detection firing (2 minutes)

```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/soc-in-a-box-detect-mass-iam \
  --start-time $(date -d '30 minutes ago' +%s000) \
  --query 'events[*].message' --output text
```

"Here you can see the Lambda was invoked automatically by EventBridge
when CloudTrail delivered the log file. It scanned the file, found
7 IAM write operations from the same identity, and triggered the
Step Functions playbook."

### 6. Show the Step Functions playbook (1 minute)

Open AWS Console → Step Functions → `soc-in-a-box-incident-response`

"The playbook runs in 4 stages: notify via SNS, route by severity,
contain the identity for HIGH findings, document the incident to S3.
This is the automation that replaces a tier-1 analyst's first 15
minutes of response."

### 7. Close with the cost story (1 minute)

"The entire stack costs $0.50/month to run — that's the VPC Flow Log
delivery. Everything else is Free Tier. The design decisions that
got it there are documented in ARCHITECTURE-DECISIONS.md — S3 over
OpenSearch, SSE-S3 over KMS, Express over Standard Step Functions,
custom Lambda over GuardDuty. Each one is a deliberate trade-off I
can defend."

---

## Common Interview Questions

**"Why not just use GuardDuty?"**
"GuardDuty is ~$1.50/month and Security Hub adds ~$2.10/month. At
scale that's thousands of dollars. More importantly, it's a black box
— you don't know what it detects or why. My custom rules cover the
same high-value patterns and I know exactly what I'm detecting and
what I'm trading away."

**"What would you add in production?"**
"KMS + Object Lock for compliance-grade immutable logs, OpenSearch for
real-time correlation alongside the Athena batch layer, a multi-region
CloudTrail trail, and a proper CICD pipeline with automated Terraform
plan approval rather than auto-approve."

**"How does this scale?"**
"The S3 + Athena pattern is what AWS uses for Amazon Security Lake —
it scales to petabytes. Lambda concurrency handles parallel file
processing. The only bottleneck would be Athena query concurrency
at very high query rates, which you'd solve with reserved capacity
or by adding an OpenSearch layer for hot data."

**"What's the detection latency?"**
"CloudTrail delivers log files every ~10 minutes. Lambda fires within
seconds of delivery. So worst case is about 10 minutes from event to
detection — acceptable for IAM and API-level threats, not for
real-time network threats where you'd need a streaming solution."
