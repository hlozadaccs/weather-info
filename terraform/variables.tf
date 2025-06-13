variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

variable "ttl_hours" {
  description = "Time to live in hours for DynamoDB TTL"
  type        = number
  default     = 24
}

variable "owm_api_key" {
  description = "OpenWeatherMap API Key"
  type        = string
  sensitive   = true
}
