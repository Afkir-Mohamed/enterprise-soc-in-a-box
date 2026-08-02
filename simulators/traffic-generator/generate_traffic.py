"""
traffic_generator.py
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Generates realistic baseline AWS API activity so Grafana dashboards
have meaningful data and the detection Lambdas have a normal
baseline to compare against.

Simulates a typical cloud engineer's working day:
  - S3 bucket listing and object reads
  - EC2 describe calls (instances, security groups, subnets)
  - IAM list calls (read-only, not writes)
  - STS get-caller-identity (health checks)

Run as a k3s CronJob every 15 minutes during business hours.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""

import boto3
import logging
import random
import time
import os

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

REGION = os.environ.get("AWS_DEFAULT_REGION", "eu-central-1")
BUCKET = os.environ.get("DATA_LAKE_BUCKET", "soc-in-a-box-627327986089-dev")


def run_s3_activity(s3):
    """Simulate normal S3 read activity."""
    logger.info("Simulating S3 activity...")
    try:
        s3.get_bucket_versioning(Bucket=BUCKET)
        s3.get_bucket_encryption(Bucket=BUCKET)
        s3.list_objects_v2(Bucket=BUCKET, Prefix="cloudtrail/", MaxKeys=10)
        logger.info("S3 activity done")
    except Exception as e:
        logger.warning(f"S3 activity error (non-fatal): {e}")


def run_ec2_activity(ec2):
    """Simulate normal EC2 describe activity."""
    logger.info("Simulating EC2 activity...")
    try:
        ec2.describe_vpcs()
        ec2.describe_subnets()
        ec2.describe_security_groups()
        ec2.describe_instances(MaxResults=10)
        logger.info("EC2 activity done")
    except Exception as e:
        logger.warning(f"EC2 activity error (non-fatal): {e}")


def run_iam_activity(iam):
    """Simulate normal IAM read activity (no writes)."""
    logger.info("Simulating IAM read activity...")
    try:
        iam.list_users(MaxItems=10)
        iam.list_roles(MaxItems=10)
        iam.get_account_summary()
        logger.info("IAM read activity done")
    except Exception as e:
        logger.warning(f"IAM activity error (non-fatal): {e}")


def run_sts_activity(sts):
    """Simulate STS health check calls."""
    logger.info("Simulating STS activity...")
    try:
        identity = sts.get_caller_identity()
        logger.info(f"STS identity confirmed: {identity.get('Arn')}")
    except Exception as e:
        logger.warning(f"STS activity error (non-fatal): {e}")


def main():
    logger.info(f"Starting traffic generator — region: {REGION}, bucket: {BUCKET}")

    session = boto3.Session(region_name=REGION)
    s3  = session.client("s3")
    ec2 = session.client("ec2")
    iam = session.client("iam")
    sts = session.client("sts")

    # Run each activity with small random delays to look realistic
    run_sts_activity(sts)
    time.sleep(random.uniform(1, 3))

    run_s3_activity(s3)
    time.sleep(random.uniform(1, 3))

    run_ec2_activity(ec2)
    time.sleep(random.uniform(1, 3))

    run_iam_activity(iam)

    logger.info("Traffic generation complete")


if __name__ == "__main__":
    main()
