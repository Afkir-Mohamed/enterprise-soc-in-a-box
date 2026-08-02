"""
detect_mass_iam.py
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Detection: Mass IAM changes (potential privilege escalation)
Severity:  HIGH
MITRE:     T1136.003 - Create Account: Cloud Account
           T1098     - Account Manipulation

What it detects:
  More than 5 IAM write operations in a single CloudTrail log file
  by the same identity. A CloudTrail file covers ~10 minutes, so
  this is effectively a "5 IAM writes in 10 minutes" rule — the
  same threshold as the Athena query in queries/iam/detections.sql.

  Detected actions include: CreateUser, CreateRole, AttachUserPolicy,
  AttachRolePolicy, CreateAccessKey, AddUserToGroup, and more.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""

import boto3
import gzip
import json
import os
import logging
from collections import defaultdict
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3  = boto3.client("s3")
sfn = boto3.client("stepfunctions")

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]
ENVIRONMENT       = os.environ.get("ENVIRONMENT", "dev")
THRESHOLD         = int(os.environ.get("IAM_WRITE_THRESHOLD", "5"))

IAM_WRITE_ACTIONS = {
    "CreateUser", "DeleteUser", "CreateRole", "DeleteRole",
    "AttachUserPolicy", "DetachUserPolicy", "AttachRolePolicy",
    "DetachRolePolicy", "CreateAccessKey", "DeleteAccessKey",
    "UpdateAccessKey", "PutUserPolicy", "DeleteUserPolicy",
    "AddUserToGroup", "RemoveUserFromGroup", "CreateGroup",
    "DeleteGroup", "UpdateLoginProfile", "CreateLoginProfile",
}


def lambda_handler(event, context):
    findings = []

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key    = record["s3"]["object"]["key"]

        if "CloudTrail-Digest" in key or not key.endswith(".json.gz"):
            continue

        logger.info(f"Processing: s3://{bucket}/{key}")
        ct_events = download_and_parse(bucket, key)
        finding   = check_mass_iam(ct_events, bucket, key)
        if finding:
            findings.append(finding)

    for finding in findings:
        trigger_response(finding)

    return {"statusCode": 200, "findings": len(findings)}


def download_and_parse(bucket: str, key: str) -> list:
    try:
        response   = s3.get_object(Bucket=bucket, Key=key)
        compressed = response["Body"].read()
        raw        = gzip.decompress(compressed)
        return json.loads(raw).get("Records", [])
    except Exception as e:
        logger.error(f"Failed to read s3://{bucket}/{key}: {e}")
        return []


def check_mass_iam(ct_events: list, bucket: str, key: str) -> dict | None:
    # Group IAM write events by identity ARN
    by_identity = defaultdict(list)

    for ct_event in ct_events:
        if (ct_event.get("eventSource") == "iam.amazonaws.com"
                and ct_event.get("eventName") in IAM_WRITE_ACTIONS):
            arn = ct_event.get("userIdentity", {}).get("arn", "unknown")
            by_identity[arn].append(ct_event)

    # Fire on any identity that exceeded the threshold
    for arn, events in by_identity.items():
        if len(events) >= THRESHOLD:
            actions = list({e["eventName"] for e in events})
            source_ips = list({e.get("sourceIPAddress", "") for e in events})
            return {
                "detection_type":  "MASS_IAM_CHANGES",
                "severity":        "HIGH",
                "identity_arn":    arn,
                "event_count":     len(events),
                "threshold":       THRESHOLD,
                "actions_taken":   actions,
                "source_ips":      source_ips,
                "first_event":     events[0].get("eventTime"),
                "last_event":      events[-1].get("eventTime"),
                "s3_source":       f"s3://{bucket}/{key}",
                "detected_at":     datetime.now(timezone.utc).isoformat(),
                "environment":     ENVIRONMENT,
                "summary": (
                    f"[HIGH] Mass IAM changes: {arn} performed "
                    f"{len(events)} IAM write operations "
                    f"({', '.join(actions[:3])}{'...' if len(actions) > 3 else ''}) "
                    f"from {', '.join(source_ips)}"
                ),
            }
    return None


def trigger_response(finding: dict):
    execution_name = (
        f"iam-{finding['identity_arn'].split('/')[-1][:12]}-"
        f"{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')}"
    )
    try:
        sfn.start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            name=execution_name,
            input=json.dumps(finding),
        )
        logger.info(f"Started Step Functions execution: {execution_name}")
    except Exception as e:
        logger.error(f"Failed to start Step Functions execution: {e}")
