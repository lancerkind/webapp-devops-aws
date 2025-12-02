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


variable "commit_sha" {
  description = "Commit SHA used to version the application artifact and EB Application Version"
  type        = string
}

variable "ssh_public_key" {
  description = "Public SSH key string to register in AWS and attach to the webapp EC2 instances"
  type        = string
}
