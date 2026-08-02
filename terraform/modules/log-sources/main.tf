# ─────────────────────────────────────────────────────────────────
# LOG SOURCES MODULE
#
# Three things happen here:
#   1. A minimal VPC (1 AZ, public + private subnet, NO NAT Gateway
#      — NAT costs ~$0.045/hour = ~$32/month, which blows the whole
#      "Free Tier" premise. Private subnet has no internet route;
#      that's fine, nothing in it needs outbound internet for this
#      lab).
#   2. A single-region CloudTrail trail (management events only —
#      the Free Tier trail) writing to the data lake bucket.
#   3. VPC Flow Logs published DIRECTLY to S3 (NOT CloudWatch Logs —
#      CloudWatch Logs ingestion/storage costs money past a small
#      free allowance; S3 delivery is the free-tier-friendly path).
# ─────────────────────────────────────────────────────────────────

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "soc-in-a-box-vpc" })
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
  tags   = merge(var.tags, { Name = "soc-in-a-box-igw" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = merge(var.tags, { Name = "soc-in-a-box-public" })
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = merge(var.tags, { Name = "soc-in-a-box-private" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }
  tags = merge(var.tags, { Name = "soc-in-a-box-public-rt" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
# No route table / NAT for the private subnet on purpose — see header comment.

# ── CloudTrail ─────────────────────────────────────────────────────
# Single-region, management events only = the Free Tier trail.
# is_multi_region_trail is intentionally false: a multi-region trail
# is still free, but keeping it single-region keeps the log volume
# (and the Athena partitions you'll query in Phase 2) small and easy
# to reason about for a portfolio demo. Documented as a stretch item
# to flip to multi-region later.
resource "aws_cloudtrail" "management_events" {
  name                          = "soc-in-a-box-trail"
  s3_bucket_name                = var.data_lake_bucket_id
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true # tamper-evidence, free, worth having

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = var.tags
}

# ── VPC Flow Logs → S3 (direct, not CloudWatch) ────────────────────
resource "aws_flow_log" "vpc_flow_logs" {
  vpc_id               = aws_vpc.lab.id
  log_destination_type = "s3"
  log_destination      = "${var.data_lake_bucket_arn}/vpc-flow-logs"
  traffic_type         = "ALL"

  # Parquet + per-hour partitioning keeps Athena scan costs (and,
  # since we're metering against the 1 TB/month free tier, scan
  # volume) low, and gives us Hive-style partitions for free.
  destination_options {
    file_format        = "parquet"
    per_hour_partition = true
  }

  tags = merge(var.tags, { Name = "soc-in-a-box-flow-log" })
}
