output "vpc_id" {
  value = aws_vpc.lab.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "cloudtrail_arn" {
  value = aws_cloudtrail.management_events.arn
}

output "flow_log_id" {
  value = aws_flow_log.vpc_flow_logs.id
}
