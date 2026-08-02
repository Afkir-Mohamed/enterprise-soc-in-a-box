-- ─────────────────────────────────────────────────────────────────
-- IAM THREAT HUNTING QUERIES
-- Database: soc_in_a_box | Table: cloudtrail_logs
-- Workgroup: soc-in-a-box
--
-- Run these in the Athena console or via CLI:
--   aws athena start-query-execution \
--     --query-string file://queries/iam/detections.sql \
--     --query-execution-context Database=soc_in_a_box \
--     --work-group soc-in-a-box
-- ─────────────────────────────────────────────────────────────────


-- ── QUERY 1: Root account usage ───────────────────────────────────
-- Any activity by the root account is a HIGH severity finding.
-- Root should never be used for day-to-day operations. Even a
-- successful root ConsoleLogin warrants immediate investigation.
-- MITRE ATT&CK: T1078.004 (Valid Accounts: Cloud Accounts)

SELECT
    eventtime,
    eventname,
    eventsource,
    sourceipaddress,
    useragent,
    errorcode,
    useridentity.arn    AS identity_arn,
    useridentity.type   AS identity_type
FROM cloudtrail_logs
WHERE year = '2026'
  AND month = '07'
  AND useridentity.type = 'Root'
  AND eventtype != 'AwsServiceEvent'
ORDER BY eventtime DESC;


-- ── QUERY 2: Console logins without MFA ───────────────────────────
-- A console login by an IAM user without MFA is a MEDIUM/HIGH
-- finding depending on the user's privilege level. For an admin
-- user (like Mohamed-Afkir-IAM-Admin) it should be HIGH.
-- MITRE ATT&CK: T1078 (Valid Accounts)

SELECT
    eventtime,
    useridentity.arn        AS identity_arn,
    useridentity.username   AS username,
    sourceipaddress,
    useragent,
    JSON_EXTRACT_SCALAR(responseelements, '$.ConsoleLogin') AS login_result,
    JSON_EXTRACT_SCALAR(requestparameters, '$.mfaType')     AS mfa_type
FROM cloudtrail_logs
WHERE year = '2026'
  AND month = '07'
  AND eventname = 'ConsoleLogin'
  AND useridentity.type = 'IAMUser'
  AND (
        responseelements LIKE '%Success%'
    AND (
          requestparameters NOT LIKE '%mfa%'
       OR requestparameters IS NULL
    )
  )
ORDER BY eventtime DESC;


-- ── QUERY 3: Mass IAM changes (potential privilege escalation) ─────
-- More than 5 IAM write operations in a 10-minute window by the
-- same identity is suspicious — could indicate an attacker who
-- has compromised credentials and is creating backdoor users/roles.
-- MITRE ATT&CK: T1136.003 (Create Account: Cloud Account)
--               T1098 (Account Manipulation)

SELECT
    useridentity.arn    AS identity_arn,
    sourceipaddress,
    DATE_TRUNC('hour', CAST(eventtime AS TIMESTAMP))  AS hour_window,
    COUNT(*)            AS iam_write_count,
    ARRAY_JOIN(ARRAY_AGG(DISTINCT eventname), ', ') AS actions_taken
FROM cloudtrail_logs
WHERE year = '2026'
  AND month = '07'
  AND eventsource = 'iam.amazonaws.com'
  AND eventname IN (
    'CreateUser', 'DeleteUser', 'CreateRole', 'DeleteRole',
    'AttachUserPolicy', 'DetachUserPolicy', 'AttachRolePolicy',
    'DetachRolePolicy', 'CreateAccessKey', 'DeleteAccessKey',
    'UpdateAccessKey', 'PutUserPolicy', 'DeleteUserPolicy',
    'AddUserToGroup', 'RemoveUserFromGroup', 'CreateGroup',
    'DeleteGroup', 'UpdateLoginProfile', 'CreateLoginProfile'
  )
GROUP BY
    useridentity.arn,
    sourceipaddress,
    DATE_TRUNC('hour', CAST(eventtime AS TIMESTAMP))
HAVING COUNT(*) > 5
ORDER BY iam_write_count DESC;


-- ── QUERY 4: New access keys created ──────────────────────────────
-- Any new access key creation should be audited. Attackers who
-- gain console access often create access keys for persistent
-- programmatic access even after the console session ends.
-- MITRE ATT&CK: T1098.001 (Account Manipulation: Additional
--               Cloud Credentials)

SELECT
    eventtime,
    useridentity.arn        AS actor_arn,
    useridentity.username   AS actor_username,
    sourceipaddress,
    JSON_EXTRACT_SCALAR(requestparameters, '$.userName') AS key_created_for_user,
    errorcode
FROM cloudtrail_logs
WHERE year = '2026'
  AND month = '07'
  AND eventname = 'CreateAccessKey'
ORDER BY eventtime DESC;
