# Teardown Guide

Run this when you want to stop all AWS resources and billing.
Takes about 5 minutes. Everything can be redeployed with
`terraform apply` when needed.

## Step 1 — Destroy Terraform-managed resources

```bash
cd ~/enterprise-soc-in-a-box/terraform/environments/dev
terraform destroy -auto-approve
```

## Step 2 — Delete the Glue table (created manually, not in Terraform)

```bash
aws glue delete-table --database-name soc_in_a_box --name cloudtrail_logs
aws glue delete-database --name soc_in_a_box
```

## Step 3 — Empty and delete the data lake bucket (versioned)

```bash
# Delete all object versions
aws s3api delete-objects \
  --bucket soc-in-a-box-627327986089-dev \
  --delete "$(aws s3api list-object-versions \
    --bucket soc-in-a-box-627327986089-dev \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json)" 2>/dev/null

# Delete all delete markers
aws s3api delete-objects \
  --bucket soc-in-a-box-627327986089-dev \
  --delete "$(aws s3api list-object-versions \
    --bucket soc-in-a-box-627327986089-dev \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
    --output json)" 2>/dev/null

# Delete the bucket
aws s3 rb s3://soc-in-a-box-627327986089-dev --force
aws s3 rb s3://soc-in-a-box-athena-627327986089-dev --force
```

## Step 4 — Destroy bootstrap resources

```bash
cd ~/enterprise-soc-in-a-box/bootstrap
aws s3 rm s3://soc-in-a-box-tfstate-7b2b6b9c --recursive
terraform destroy -auto-approve
```

## Step 5 — Verify nothing is left running

```bash
aws cloudtrail describe-trails \
  --query 'trailList[?Name==`soc-in-a-box-trail`]'
aws lambda list-functions \
  --query 'Functions[?starts_with(FunctionName, `soc-in-a-box`)]'
aws stepfunctions list-state-machines \
  --query 'stateMachines[?starts_with(name, `soc-in-a-box`)]'
aws sns list-topics \
  --query 'Topics[?contains(TopicArn, `soc-in-a-box`)]'
```

All should return `[]`.

## To redeploy

```bash
cd ~/enterprise-soc-in-a-box/bootstrap
terraform apply -auto-approve

cd ~/enterprise-soc-in-a-box/terraform/environments/dev
terraform apply -auto-approve
```
