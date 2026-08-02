-- ─────────────────────────────────────────────────────────────────
-- ACCOUNT-LEVEL THREAT HUNTING QUERIES
-- Database: soc_in_a_box | Table: cloudtrail_logs
-- ─────────────────────────────────────────────────────────────────


-- ── QUERY 1: Failed authentication attempts (brute force) ─────────
-- A spike in AccessDenied or AuthFailure errors from a single IP
-- indicates credential stuffing or brute force attempts.
-- MITRE ATT&CK: T1110 (Brute Force)

SELECT
    sourceipaddress,
    useridentity.arn        AS identity_arn,
    errorcode,
    COUNT(*)                AS failure_count,
    MIN(eventtime)          AS first_seen,
    MAX(eventtime)          AS last_seen,
    ARRAY_JOIN(ARRAY_AGG(DISTINCT eventname), ', ') AS failed_actions
FROM cloudtrail_logs
WHERE year = '2026'
  AND month = '07'
  AND errorcode IN (
    'AccessDenied',
    'AuthFailure',
    'UnauthorizedOperation',
    'InvalidClientTokenId',
    'ExpiredTokenException'
  )
GROUP BY sourceipaddress, useridentity.arn, errorcode
HAVING COUNT(*) > 3
ORDER BY failure_count DESC;


-- ── QUERY 2: S3 bucket made public ────────────────────────────────
-- Any change to S3 bucket ACLs or public access settings is
-- critical — data exfiltration often starts with making a bucket
-- public. One of the most common cloud breach patterns.
-- MITRE ATT&CK: T1530 (Data from Cloud Storage)

SELECT
    eventtime,
    eventname,
    useridentity.arn    AS identity_arn,
    sourceipaddress,
    requestparameters,
    errorcode
FROM cloudtrail_logs
WHERE year = '2026'
  AND month = '07'
  AND eventsource = 's3.amazonaws.com'
  AND eventname IN (
    'PutBucketAcl',
    'PutBucketPolicy',
    'DeleteBucketPolicy',
    'PutBucketPublicAccessBlock',
    'DeletePublicAccessBlock'
  )
ORDER BY eventtime DESC;


-- ── QUERY 3: Secrets Manager / SSM Parameter Store access ─────────
-- Unusual access to secrets is a strong indicator of credential
-- harvesting after initial compromise.
-- MITRE ATT&CK: T1552.004 (Unsecured Credentials: Private Keys)

SELECT
    eventtime,
    eventsource,
    eventname,
    useridentity.arn    AS identity_arn,
    sourceipaddress,
    requestparameters,
    errorcode
FROM cloudtrail_logs
WHERE year = '2026'
  AND month = '07'
  AND eventsource IN (
    'secretsmanager.amazonaws.com',
    'ssm.amazonaws.com'
  )
  AND eventname IN (
    'GetSecretValue',
    'DescribeSecret',
    'GetParameter',
    'GetParameters',
    'GetParametersByPath'
  )
ORDER BY eventtime DESC;


-- ── QUERY 4: Full account activity summary (daily rollup) ─────────
-- High-level daily view of activity volume by service and identity.
-- Useful for baselining normal behaviour — spikes on a given day
-- stand out immediately in Grafana.

SELECT
    SUBSTR(eventtime, 1, 10)    AS event_date,
    eventsource,
    useridentity.type           AS identity_type,
    useridentity.arn            AS identity_arn,
    COUNT(*)                    AS total_events,
    COUNT(DISTINCT eventname)   AS unique_actions,
    COUNT(DISTINCT sourceipaddress) AS unique_source_ips
FROM cloudtrail_logs
WHERE year = '2026'
  AND month = '07'
GROUP BY
    SUBSTR(eventtime, 1, 10),
    eventsource,
    useridentity.type,
    useridentity.arn
ORDER BY event_date DESC, total_events DESC;
