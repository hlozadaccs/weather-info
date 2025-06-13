output "lambda_function_name" {
  description = "Name of the deployed Lambda function"
  value       = aws_lambda_function.weather_info.function_name
}

output "api_gateway_url" {
  description = "Invoke URL of the API Gateway"
  value       = aws_apigatewayv2_api.api.api_endpoint
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for traceability"
  value       = aws_dynamodb_table.weather_info_table.name
}

output "parameter_name" {
  description = "SSM Parameter used for the OpenWeatherMap API Key"
  value       = aws_ssm_parameter.owm_api_key.name
}
