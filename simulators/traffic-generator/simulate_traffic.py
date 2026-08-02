"""
traffic_generator.py
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Generates realistic baseline AWS API activity so CloudTrail has
normal traffic to establish a baseline against. Runs as a k3s
CronJob every 30 minutes.

Calls made (all read-only, no mutations):
  - S3: ListBuckets, GetBucketLocation
  - EC2: DescribeInstances, DescribeVpcs, DescribeSubnets
  - IAM: ListUsers, ListRoles, GetAccountSummary
  - STS: GetCallerIdentity

These show up in CloudTrail as normal IAMUser activity from the
k3s cluster's IP — giving your Grafana dashboard real baseline
data to visualize and your detection Lambdas something to NOT
fire on (verifying true-negative behaviour).
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""

import boto3
import logging
import time
import random

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

REGION = "eu-central-1"


def run_s3_calls():
    client = boto3.client("s3", region_name=REGION)
    try:
        buckets = client.list_buckets()["Buckets"]
        logger.info(f"S3: listed {len(buckets)} buckets")
        for bucket in buckets[:3]:
            try:
                client.get_bucket_location(Bucket=bucket["Name"])
                logger.info(f"S3: got location for {bucket['Name']}")
            except Exception:
                pass
        time.sleep(random.uniform(1, 3))
    except Exception as e:
        logger.error(f"S3 calls failed: {e}")


def run_ec2_calls():
    client = boto3.client("ec2", region_name=REGION)
    try:
        result = client.describe_instances()
        count = sum(len(r["Instances"]) for r in result["Reservations"])
        logger.info(f"EC2: described {count} instances")
        time.sleep(random.uniform(1, 2))

        vpcs = client.describe_vpcs()["Vpcs"]
        logger.info(f"EC2: described {len(vpcs)} VPCs")
        time.sleep(random.uniform(1, 2))

        subnets = client.describe_subnets()["Subnets"]
        logger.info(f"EC2: described {len(subnets)} subnets")
        time.sleep(random.uniform(1, 2))
    except Exception as e:
        logger.error(f"EC2 calls failed: {e}")


def run_iam_calls():
    client = boto3.client("iam", region_name=REGION)
    try:
        users = client.list_users()["Users"]
        logger.info(f"IAM: listed {len(users)} users")
        time.sleep(random.uniform(1, 2))

        roles = client.list_roles()["Roles"]
        logger.info(f"IAM: listed {len(roles)} roles")
        time.sleep(random.uniform(1, 2))

        summary = client.get_account_summary()["SummaryMap"]
        logger.info(f"IAM: got account summary ({len(summary)} metrics)")
        time.sleep(random.uniform(1, 2))
    except Exception as e:
        logger.error(f"IAM calls failed: {e}")


def run_sts_calls():
    client = boto3.client("sts", region_name=REGION)
    try:
        identity = client.get_caller_identity()
        logger.info(f"STS: caller identity confirmed — {identity['Arn']}")
    except Exception as e:
        logger.error(f"STS calls failed: {e}")


def main():
    logger.info("=== Traffic generator starting ===")
    run_sts_calls()
    run_s3_calls()
    run_ec2_calls()
    run_iam_calls()
    logger.info("=== Traffic generator complete ===")


if __name__ == "__main__":
    main()
