variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "webapp-demo"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "Asgardeo-demo"
}

variable "instance_type" {
  description = "EC2 instance type for Beanstalk"
  type        = string
  default     = "t3.micro"
}

variable "availability_zones" {
  description = "List of availability zones to use (optional). If empty, auto-detect 2 AZs."
  type        = list(string)
  default     = []
}

variable "aws_account_id" {
  description = "AWS account ID to use in S3 bucket naming (optional). If omitted, will be discovered."
  type        = string
  default     = ""
}
