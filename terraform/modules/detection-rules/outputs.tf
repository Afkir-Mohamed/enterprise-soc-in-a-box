output "state_machine_arn" {
  value = aws_sfn_state_machine.incident_response.arn
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "detect_root_function_name" {
  value = aws_lambda_function.detect_root.function_name
}

output "detect_mass_iam_function_name" {
  value = aws_lambda_function.detect_mass_iam.function_name
}

output "detect_network_recon_function_name" {
  value = aws_lambda_function.detect_network_recon.function_name
}
