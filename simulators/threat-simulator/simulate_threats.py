"""
threat_simulator.py
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Simulates attack patterns that trigger the detection Lambdas.
Runs as a k3s CronJob on demand (not scheduled — run manually
before a demo to generate findings).

Scenarios:
  1. MASS_IAM_CHANGES — creates a temp IAM user, attaches/detaches
     policies rapidly, then cleans up. Triggers detect-mass-iam.

  2. UNUSUAL_REGION — makes EC2 describe calls in ap-southeast-1
     (Singapore), which is outside the allowed regions list.
     Triggers detect-network-recon.

  3. CLOUDTRAIL_RECON — calls describe/list on CloudTrail itself,
     simulating an attacker mapping the logging setup before
     attempting to disable it. Useful for demonstrating the
     network/detections.sql query #3.

ROOT SIMULATION: deliberately omitted. Using the actual root
account would be a real security event. The detect-root-activity
Lambda is verified by reviewing the code + unit tests rather
than live simulation. Document this in interview: "I deliberately
didn't simulate root usage against a live account — I verified
the detection logic through code review and would test it in a
dedicated sandbox account."
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""

import boto3
import logging
import time
import sys
import argparse

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

REGION       = "eu-central-1"
TEST_USER    = "soc-simulator-test-user"
TEST_POLICY  = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"


# ── Scenario 1: Mass IAM Changes ───────────────────────────────────
def simulate_mass_iam_changes():
    """
    Performs 6+ IAM write operations rapidly to trigger the
    detect-mass-iam Lambda (threshold: 5 writes per log file).

    Cleans up after itself — the test user is deleted at the end.
    Safe to run repeatedly.
    """
    logger.info("=== SCENARIO 1: Mass IAM Changes ===")
    iam = boto3.client("iam", region_name=REGION)

    try:
        # 1. CreateUser
        logger.info(f"IAM: CreateUser {TEST_USER}")
        iam.create_user(UserName=TEST_USER)
        time.sleep(1)

        # 2. AttachUserPolicy
        logger.info("IAM: AttachUserPolicy")
        iam.attach_user_policy(UserName=TEST_USER, PolicyArn=TEST_POLICY)
        time.sleep(1)

        # 3. DetachUserPolicy
        logger.info("IAM: DetachUserPolicy")
        iam.detach_user_policy(UserName=TEST_USER, PolicyArn=TEST_POLICY)
        time.sleep(1)

        # 4. CreateLoginProfile (simulate console access grant)
        logger.info("IAM: CreateLoginProfile")
        iam.create_login_profile(
            UserName=TEST_USER,
            Password="Temp@12345!",
            PasswordResetRequired=True
        )
        time.sleep(1)

        # 5. UpdateLoginProfile
        logger.info("IAM: UpdateLoginProfile")
        iam.update_login_profile(
            UserName=TEST_USER,
            Password="Temp@67890!",
            PasswordResetRequired=True
        )
        time.sleep(1)

        # 6. CreateAccessKey
        logger.info("IAM: CreateAccessKey")
        key = iam.create_access_key(UserName=TEST_USER)["AccessKey"]
        time.sleep(1)

        # 7. UpdateAccessKey (deactivate)
        logger.info("IAM: UpdateAccessKey (deactivate)")
        iam.update_access_key(
            UserName=TEST_USER,
            AccessKeyId=key["AccessKeyId"],
            Status="Inactive"
        )
        time.sleep(1)

        logger.info("Scenario 1 complete — 7 IAM writes generated")
        logger.info("Detection should fire within ~10 minutes when CloudTrail delivers the log file")

    except Exception as e:
        logger.error(f"Scenario 1 error: {e}")
    finally:
        # Always clean up — leave no test artifacts
        logger.info("Cleaning up test user...")
        _cleanup_test_user(iam)


def _cleanup_test_user(iam):
    try:
        # Delete access keys
        keys = iam.list_access_keys(UserName=TEST_USER)["AccessKeyMetadata"]
        for key in keys:
            iam.delete_access_key(UserName=TEST_USER, AccessKeyId=key["AccessKeyId"])

        # Delete login profile
        try:
            iam.delete_login_profile(UserName=TEST_USER)
        except iam.exceptions.NoSuchEntityException:
            pass

        # Detach policies
        policies = iam.list_attached_user_policies(UserName=TEST_USER)["AttachedPolicies"]
        for policy in policies:
            iam.detach_user_policy(UserName=TEST_USER, PolicyArn=policy["PolicyArn"])

        # Delete user
        iam.delete_user(UserName=TEST_USER)
        logger.info(f"Cleaned up: {TEST_USER} deleted")
    except Exception as e:
        logger.warning(f"Cleanup warning (may need manual cleanup): {e}")


# ── Scenario 2: Unusual Region ─────────────────────────────────────
def simulate_unusual_region():
    """
    Makes EC2 API calls in ap-southeast-1 (Singapore) — outside
    the allowed regions (eu-central-1, us-east-1). Triggers the
    detect-network-recon Lambda.

    All calls are read-only describe calls — no resources created.
    """
    logger.info("=== SCENARIO 2: Unusual Region (ap-southeast-1) ===")

    unusual_region = "ap-southeast-1"
    ec2 = boto3.client("ec2", region_name=unusual_region)

    try:
        vpcs = ec2.describe_vpcs()["Vpcs"]
        logger.info(f"EC2 ({unusual_region}): described {len(vpcs)} VPCs")
        time.sleep(2)

        instances = ec2.describe_instances()
        count = sum(len(r["Instances"]) for r in instances["Reservations"])
        logger.info(f"EC2 ({unusual_region}): described {count} instances")
        time.sleep(2)

        sgs = ec2.describe_security_groups()["SecurityGroups"]
        logger.info(f"EC2 ({unusual_region}): described {len(sgs)} security groups")

        logger.info("Scenario 2 complete — 3 API calls from ap-southeast-1 generated")
        logger.info("Detection should fire within ~10 minutes when CloudTrail delivers the log file")

    except Exception as e:
        logger.error(f"Scenario 2 error: {e}")


# ── Scenario 3: CloudTrail Recon ───────────────────────────────────
def simulate_cloudtrail_recon():
    """
    Calls CloudTrail describe/list APIs — simulating an attacker
    mapping the logging infrastructure before attempting to disable
    it. Read-only, no mutations.
    """
    logger.info("=== SCENARIO 3: CloudTrail Recon ===")

    ct = boto3.client("cloudtrail", region_name=REGION)

    try:
        trails = ct.describe_trails()["trailList"]
        logger.info(f"CloudTrail: described {len(trails)} trails")
        time.sleep(1)

        for trail in trails:
            status = ct.get_trail_status(Name=trail["TrailARN"])
            logger.info(f"CloudTrail: got status for {trail['Name']} — logging={status['IsLogging']}")
            time.sleep(1)

        event_selectors = ct.get_event_selectors(TrailName=trails[0]["TrailARN"])
        logger.info(f"CloudTrail: got event selectors for {trails[0]['Name']}")

        logger.info("Scenario 3 complete — CloudTrail recon pattern generated")
        logger.info("Check queries/network/detections.sql Query #3 to find this in Athena")

    except Exception as e:
        logger.error(f"Scenario 3 error: {e}")


# ── Main ───────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="SOC-in-a-Box Threat Simulator")
    parser.add_argument(
        "--scenario",
        choices=["mass-iam", "unusual-region", "cloudtrail-recon", "all"],
        default="all",
        help="Which attack scenario to simulate"
    )
    args = parser.parse_args()

    logger.info(f"=== Threat simulator starting — scenario: {args.scenario} ===")

    if args.scenario in ("mass-iam", "all"):
        simulate_mass_iam_changes()
        time.sleep(5)

    if args.scenario in ("unusual-region", "all"):
        simulate_unusual_region()
        time.sleep(5)

    if args.scenario in ("cloudtrail-recon", "all"):
        simulate_cloudtrail_recon()

    logger.info("=== Threat simulator complete ===")
    logger.info("Wait 10-15 minutes for CloudTrail to deliver logs, then check:")
    logger.info("  1. CloudWatch Logs for Lambda execution results")
    logger.info("  2. SNS topic for any HIGH severity alerts")
    logger.info("  3. Step Functions console for state machine executions")
    logger.info("  4. Grafana dashboard for the spike in event volume")


if __name__ == "__main__":
    main()
