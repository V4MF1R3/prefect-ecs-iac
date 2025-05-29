variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "prefect_api_key" {
  description = "Prefect Cloud API Key"
  type        = string
  sensitive   = true
}

variable "prefect_api_url" {
  description = "Prefect Cloud API URL"
  type        = string
  default     = "https://api.prefect.cloud/api/accounts"
}

variable "prefect_account_id" {
  description = "Prefect Account ID"
  type        = string
}

variable "prefect_workspace_id" {
  description = "Prefect Workspace ID"
  type        = string
}

variable "work_pool_name" {
  description = "Name of the Prefect work pool"
  type        = string
  default     = "ecs-work-pool"
}

variable "prefect_image" {
  description = "Prefect Docker image"
  type        = string
  default     = "prefecthq/prefect:2-latest"
}