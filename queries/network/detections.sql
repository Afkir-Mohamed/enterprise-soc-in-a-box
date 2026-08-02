-- ─────────────────────────────────────────────────────────────────
-- NETWORK THREAT HUNTING QUERIES
-- Database: soc_in_a_box | Table: cloudtrail_logs
-- ─────────────────────────────────────────────────────────────────


-- ── QUERY 1: API calls from unusual regions ────────────────────────
-- You operate in eu-central-1. API calls from other regions could
-- indicate compromised credentials being used from a different
-- geography, or an attacker using a VPN/proxy in another region.
-- MITRE ATT&CK: T1535 (Unused/Unsupported Cloud Regions)

SELECT
    awsregion,
    eventsource,
    eventname,
    useridentity.arn    AS identity_arn,
    sourceipaddress,
    COUNT(*)            AS event_count
FROM cloudtrail_logs
WHERE year = '2026'
  AND month = '07'
  AND awsregion NOT IN ('eu-central-1', 'us-east-1')
  -- us-east-1 is excluded because global services (IAM, STS,
  -- Route53, CloudFront) always log to us-east-1 regardless of
  -- where you operate. Seeing it here is normal.
  AND useridentity.type != 'AWSService'
GROUP BY
    awsregion, eventsource, eventname,
    useridentity.arn, sourceipaddress
ORDER BY event_count DESC;


-- ── QUERY 2: Security group changes (firewall rule tampering) ──────
-- Any modification to security groups should be reviewed.
-- An attacker who gains EC2/VPC access may open inbound ports
-- (e.g. 0.0.0.0/0 on port 22/3389) to establish persistent access.
-- MITRE ATT&CK: T1562.007 (Impair Defenses: Disable or Modify
--               Cloud Firewall)

SELECT
    eventtime,
    eventname,
    useridentity.arn    AS identity_arn,
    sourceipaddress,
    requestparameters
FROM cloudtrail_logs
WHERE year = '2026'
  AND month = '07'
  AND eventsource = 'ec2.amazonaws.com'
  AND eventname IN (
    'AuthorizeSecurityGroupIngress',
    'AuthorizeSecurityGroupEgress',
    'RevokeSecurityGroupIngress',
    'RevokeSecurityGroupEgress',
    'CreateSecurityGroup',
    'DeleteSecurityGroup',
    'ModifySecurityGroupRules'
  )
ORDER BY eventtime DESC;


-- ── QUERY 3: CloudTrail tampering attempts ─────────────────────────
-- An attacker who has gained access will often try to cover their
-- tracks by disabling CloudTrail or deleting log files.
-- This is one of the most important detections to have.
-- MITRE ATT&CK: T1562.008 (Impair Defenses: Disable Cloud Logs)

SELECT
    eventtime,
    eventname,
    useridentity.arn    AS identity_arn,
    sourceipaddress,
    useragent,
    errorcode
FROM cloudtrail_logs
WHERE year = '2026'
  AND month = '07'
  AND eventsource = 'cloudtrail.amazonaws.com'
  AND eventname IN (
    'StopLogging',
    'DeleteTrail',
    'UpdateTrail',
    'PutEventSelectors',
    'RemoveTags'
  )
ORDER BY eventtime DESC;


-- ── QUERY 4: EC2 instance launched with public IP ─────────────────
-- Tracks any EC2 instance launched with a public IP — useful for
-- spotting cryptomining instances or backdoor compute spun up by
-- an attacker. Correlate with the source identity and IP.
-- MITRE ATT&CK: T1578.002 (Modify Cloud Compute Infrastructure)

SELECT
    eventtime,
    useridentity.arn        AS identity_arn,
    sourceipaddress,
    JSON_EXTRACT_SCALAR(requestparameters, '$.instanceType')    AS instance_type,
    JSON_EXTRACT_SCALAR(requestparameters, '$.imageId')         AS ami_id,
    JSON_EXTRACT_SCALAR(requestparameters, '$.subnetId')        AS subnet_id,
    errorcode
FROM cloudtrail_logs
WHERE year = '2026'
  AND month = '07'
  AND eventsource = 'ec2.amazonaws.com'
  AND eventname = 'RunInstances'
ORDER BY eventtime DESC;
