"""
detect_network_recon.py
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Detection: API calls from unusual regions
Severity:  MEDIUM
MITRE:     T1535 - Unused/Unsupported Cloud Regions

What it detects:
  Any API call by a human identity (IAMUser or AssumedRole) from
  a region outside the expected set. Global services always log
  to us-east-1 regardless of your operating region, so that's
  always in the allowed list.

  Expected regions are set via the ALLOWED_REGIONS env variable
  (comma-separated). Default: eu-central-1,us-east-1
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
ALLOWED_REGIONS   = set(
    os.environ.get("ALLOWED_REGIONS", "eu-central-1,us-east-1").split(",")
)


def lambda_handler(event, context):
    findings = []

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key    = record["s3"]["object"]["key"]

        if "CloudTrail-Digest" in key or not key.endswith(".json.gz"):
            continue

        logger.info(f"Processing: s3://{bucket}/{key}")
        ct_events = download_and_parse(bucket, key)

        for ct_event in ct_events:
            finding = check_unusual_region(ct_event, bucket, key)
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


def check_unusual_region(ct_event: dict, bucket: str, key: str) -> dict | None:
    region        = ct_event.get("awsRegion", "")
    user_identity = ct_event.get("userIdentity", {})
    identity_type = user_identity.get("type", "")

    # Only flag human identities — AWSService calls appear in
    # many regions as part of normal service operation
    if (region not in ALLOWED_REGIONS
            and identity_type in ("IAMUser", "AssumedRole")):
        return {
            "detection_type": "UNUSUAL_REGION",
            "severity":       "MEDIUM",
            "event_id":       ct_event.get("eventID"),
            "event_time":     ct_event.get("eventTime"),
            "event_name":     ct_event.get("eventName"),
            "event_source":   ct_event.get("eventSource"),
            "aws_region":     region,
            "allowed_regions": list(ALLOWED_REGIONS),
            "source_ip":      ct_event.get("sourceIPAddress"),
            "identity_arn":   user_identity.get("arn"),
            "identity_type":  identity_type,
            "s3_source":      f"s3://{bucket}/{key}",
            "detected_at":    datetime.now(timezone.utc).isoformat(),
            "environment":    ENVIRONMENT,
            "summary": (
                f"[MEDIUM] Unusual region: {user_identity.get('arn')} "
                f"called {ct_event.get('eventName')} on "
                f"{ct_event.get('eventSource')} from region {region} "
                f"(expected: {', '.join(ALLOWED_REGIONS)})"
            ),
        }
    return None


def trigger_response(finding: dict):
    execution_name = (
        f"region-{finding['aws_region']}-"
        f"{finding['event_id'][:8]}-"
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
