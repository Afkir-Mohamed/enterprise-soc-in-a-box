"""
detect_root_activity.py
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Detection: Root account usage
Severity:  HIGH
MITRE:     T1078.004 - Valid Accounts: Cloud Accounts

Trigger:
  EventBridge rule fires when a new .json.gz file lands in the
  cloudtrail/ prefix of the data lake bucket. This Lambda downloads
  the file, decompresses it, and scans every event for root activity.

What it detects:
  Any API call where userIdentity.type == "Root" and the event is
  NOT an AWSServiceEvent (background service calls don't count).
  Even a single root event is HIGH severity — root should never
  be used for day-to-day operations.

What happens on a finding:
  Publishes a structured finding to SNS, which triggers the Step
  Functions incident response state machine.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""

import boto3
import gzip
import json
import os
import logging
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3  = boto3.client("s3")
sfn = boto3.client("stepfunctions")

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]
ENVIRONMENT       = os.environ.get("ENVIRONMENT", "dev")


def lambda_handler(event, context):
    findings = []

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key    = record["s3"]["object"]["key"]

        if "CloudTrail-Digest" in key or not key.endswith(".json.gz"):
            logger.info(f"Skipping non-log file: {key}")
            continue

        logger.info(f"Processing: s3://{bucket}/{key}")
        ct_events = download_and_parse(bucket, key)

        for ct_event in ct_events:
            finding = check_root_activity(ct_event, bucket, key)
            if finding:
                findings.append(finding)

    if findings:
        logger.warning(f"Found {len(findings)} root activity event(s)")
        for finding in findings:
            trigger_response(finding)
    else:
        logger.info("No root activity detected")

    return {"statusCode": 200, "findings": len(findings)}


def download_and_parse(bucket: str, key: str) -> list:
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        compressed = response["Body"].read()
        raw        = gzip.decompress(compressed)
        data       = json.loads(raw)
        return data.get("Records", [])
    except Exception as e:
        logger.error(f"Failed to read s3://{bucket}/{key}: {e}")
        return []


def check_root_activity(ct_event: dict, bucket: str, key: str) -> dict | None:
    user_identity = ct_event.get("userIdentity", {})
    event_type    = ct_event.get("eventType", "")

    if user_identity.get("type") == "Root" and event_type != "AwsServiceEvent":
        return {
            "detection_type": "ROOT_ACTIVITY",
            "severity":       "HIGH",
            "event_id":       ct_event.get("eventID"),
            "event_time":     ct_event.get("eventTime"),
            "event_name":     ct_event.get("eventName"),
            "event_source":   ct_event.get("eventSource"),
            "source_ip":      ct_event.get("sourceIPAddress"),
            "user_agent":     ct_event.get("userAgent"),
            "aws_region":     ct_event.get("awsRegion"),
            "error_code":     ct_event.get("errorCode"),
            "identity_arn":   user_identity.get("arn", "root"),
            "identity_type":  user_identity.get("type"),
            "s3_source":      f"s3://{bucket}/{key}",
            "detected_at":    datetime.now(timezone.utc).isoformat(),
            "environment":    ENVIRONMENT,
            "summary": (
                f"[HIGH] Root account used: {ct_event.get('eventName')} "
                f"on {ct_event.get('eventSource')} "
                f"from {ct_event.get('sourceIPAddress')} "
                f"at {ct_event.get('eventTime')}"
            ),
        }
    return None


def trigger_response(finding: dict):
    execution_name = (
        f"root-{finding['event_id'][:8]}-"
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
