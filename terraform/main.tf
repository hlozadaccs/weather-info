provider "aws" {
  region = var.aws_region
}

###################
# Lambda Function #
###################

resource "aws_iam_role" "lambda_exec_role" {
  name = "weather_info_lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Effect = "Allow",
      Sid    = ""
    }]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name = "weather_info_lambda_policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow",
        Action = [
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:GetItem"
        ],
        Resource = [
          "arn:aws:dynamodb:us-west-2:814888277417:table/weather-info-trace",
          "arn:aws:dynamodb:us-west-2:814888277417:table/weather-info-trace/index/ip-timestamp-index"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameter"
        ],
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/weather-info/openweathermap-api-key"
      }
    ]
  })
}

resource "aws_ssm_parameter" "owm_api_key" {
  name        = "/weather-info/openweathermap-api-key"
  type        = "SecureString"
  value       = var.owm_api_key
  overwrite   = true
  description = "API Key for OpenWeatherMap"
  tags = {
    Name = "weather-info-owm-key"
  }
}


resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_lambda_function" "weather_info" {
  function_name = "weather-info-lambda"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30
  memory_size   = 256

  filename         = "${path.module}/../lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda.zip")

  environment {
    variables = {
      REGION               = var.aws_region
      DYNAMODB_TABLE       = aws_dynamodb_table.weather_info_table.name
      DYNAMODB_TTL_HOURS   = var.ttl_hours
    }
  }
}

##################
# API Gateway    #
##################

resource "aws_apigatewayv2_api" "api" {
  name          = "weather-info-api"
  protocol_type = "HTTP"
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.weather_info.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id             = aws_apigatewayv2_api.api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.weather_info.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /weather-info"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

#####################
# DynamoDB Table    #
#####################

resource "aws_dynamodb_table" "weather_info_table" {
  name         = "weather-info-trace"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  range_key    = "timestamp"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  attribute {
    name = "ip"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  global_secondary_index {
    name            = "ip-timestamp-index"
    hash_key        = "ip"
    range_key       = "timestamp"
    projection_type = "ALL"
  }
}

data "aws_caller_identity" "current" {}
