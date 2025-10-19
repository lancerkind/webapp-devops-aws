output "beanstalk_environment_url" {
  description = "URL of the Beanstalk environment"
  value       = aws_elastic_beanstalk_environment.asgardeo_environment.endpoint_url
}

output "beanstalk_environment_id" {
  description = "ID of the Beanstalk environment"
  value       = aws_elastic_beanstalk_environment.asgardeo_environment.id
}

output "vpc_id" {
  description = "The VPC ID created"
  value       = aws_vpc.asgardeo_vpc.id
}

output "artifacts_bucket_name" {
  description = "Name of the S3 bucket storing application artifacts"
  value       = aws_s3_bucket.artifacts.bucket
}
