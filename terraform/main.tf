terraform {
  backend "s3" {
    bucket = "asgardeo-dev-905418390803-tfstate"
    key    = "global/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  effective_account_id = var.aws_account_id != "" ? var.aws_account_id : data.aws_caller_identity.current.account_id
  name_prefix          = "asgardeo"
}

# Notes on Terraform syntax:
#resource "<resource_type>" "<local_name>" {
#  <configuration arguments>
#}
#### Breaking It Down
#1. **`resource`** - The keyword that tells Terraform "I'm declaring a resource"
#2. **`"<resource_type>"`** - What **kind** of AWS resource (from the provider)
#    - Examples: , , `aws_vpc``aws_s3_bucket``aws_iam_role`
#    - This is defined by the AWS provider
#
#3. **`"<local_name>"`** - **Your** name for this specific instance
#    - This is how you reference it elsewhere in your code
#    - You choose this name (like a variable name)
#
#4. **`{ ... }`** - The **configuration** for this resource
#    - Not "work to perform" but rather "properties to set"
#    - These are the **arguments** that define how the resource should be created
# The statements inside `{ }` are **declarative**, not imperative:
#- ❌ Not: "Do this work"
#- ✅ Instead: "I want a resource with these properties"
#
#Terraform figures out the work needed to make reality match your declaration.


# VPC
resource "aws_vpc" "asgardeo_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.asgardeo_vpc.id
  tags   = merge(local.tags, { Name = "${local.name_prefix}-igw" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.asgardeo_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = merge(local.tags, { Name = "${local.name_prefix}-public-rt" })
}

# 2 public subnets
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.asgardeo_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.asgardeo_vpc.cidr_block, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-public-${count.index + 1}" })
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Group
# Security Groups
# Webapp SG (public HTTP)
resource "aws_security_group" "webapp_sg" {
  name        = "${local.name_prefix}-webapp-sg"
  description = "Allow public HTTP for webapp"
  vpc_id      = aws_vpc.asgardeo_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-webapp-sg" })
}

# Service Load Balancer SG (internal; allow only from webapp SG)
resource "aws_security_group" "service_elb_sg" {
  name        = "${local.name_prefix}-service-elb-sg"
  description = "Internal LB for time-service; allow from webapp SG on port 80"
  vpc_id      = aws_vpc.asgardeo_vpc.id

  ingress {
    # Elastic Beanstalk load balancers (Classic/ALB) listen on port 80 by default
    # and forward to the instance's nginx on port 80, which then proxies to the app port.
    # Allow the webapp SG to reach the service LB on port 80.
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.webapp_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-service-elb-sg" })
}

# Service Instance SG (allow only from its LB on port 80)
resource "aws_security_group" "service_instance_sg" {
  name        = "${local.name_prefix}-service-instance-sg"
  description = "Allow traffic from service LB on port 80 (nginx)"
  vpc_id      = aws_vpc.asgardeo_vpc.id

  ingress {
    # The load balancer forwards to instance port 80 (nginx), which then proxies to the app port.
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.service_elb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-service-instance-sg" })
}

# IAM roles and instance profile
resource "aws_iam_role" "beanstalk_ec2_role" {
  name = "${local.name_prefix}-beanstalk-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# This EC2 profile will need a policy setup permissions to write logs and other AWS paperwork for running the application,
# and we'll want it to be able to access the s3 bucket
# to copy the wep app package.
resource "aws_iam_instance_profile" "beanstalk_ec2_profile" {
  name = "${local.name_prefix}-beanstalk-ec2-profile"
  role = aws_iam_role.beanstalk_ec2_role.name
}

# Attach AWS managed policies for web tier
resource "aws_iam_role_policy_attachment" "ec2_webtier" {
  role       = aws_iam_role.beanstalk_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

# Optional: allow S3 access for instances (static app normally not needed, but safe)
resource "aws_iam_role_policy_attachment" "ec2_s3_read" {
  role       = aws_iam_role.beanstalk_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# Service role for Elastic Beanstalk
resource "aws_iam_role" "beanstalk_service_role" {
  name = "${local.name_prefix}-beanstalk-service-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "elasticbeanstalk.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "service_enhanced_health" {
  role       = aws_iam_role.beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

# S3 bucket for application bundles
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

locals {
  artifacts_bucket_name = lower(replace("${local.name_prefix}-artifacts-${local.effective_account_id}-${random_id.bucket_suffix.hex}", " ", "-"))
}

resource "aws_s3_bucket" "artifacts" {
  bucket = local.artifacts_bucket_name
  tags   = merge(local.tags, { Name = local.artifacts_bucket_name })
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Elastic Beanstalk Application
resource "aws_elastic_beanstalk_application" "asgardeo_application" {
  name        = "asgardeo-webapp-demo"
  description = "Demo application for Asgardeo"

  tags = local.tags
}

# Upload webapp bundle to S3
resource "aws_s3_object" "webapp_bundle" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "webapp-${var.commit_sha}.zip"
  source = "${path.module}/../webapp.zip"
  etag   = filemd5("${path.module}/../webapp.zip")
}

## Service bundle (time-service)
resource "aws_s3_object" "service_bundle" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "service-${var.commit_sha}.zip"
  source = "${path.module}/../service.zip"
  etag   = filemd5("${path.module}/../service.zip")
}

# Application Versions
resource "aws_elastic_beanstalk_application_version" "asgardeo_app_version" {
  name        = "v-${var.commit_sha}"
  application = aws_elastic_beanstalk_application.asgardeo_application.name
  description = "Version for commit ${var.commit_sha}"
  bucket      = aws_s3_bucket.artifacts.id
  key         = aws_s3_object.webapp_bundle.key
}

resource "aws_elastic_beanstalk_application_version" "service_app_version" {
  name        = "service-v-${var.commit_sha}"
  application = aws_elastic_beanstalk_application.asgardeo_application.name
  description = "Service version for commit ${var.commit_sha}"
  bucket      = aws_s3_bucket.artifacts.id
  key         = aws_s3_object.service_bundle.key
}

# Elastic Beanstalk Environment
resource "aws_elastic_beanstalk_environment" "asgardeo_environment" {
  name                = "asgardeo-webapp-demo-env"
  application         = aws_elastic_beanstalk_application.asgardeo_application.name
  solution_stack_name = "64bit Amazon Linux 2023 v6.6.6 running Node.js 22"
  version_label       = aws_elastic_beanstalk_application_version.asgardeo_app_version.name

  # Environment configuration
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.beanstalk_ec2_profile.name
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.asgardeo_vpc.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", [for s in aws_subnet.public : s.id])
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.webapp_sg.id
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "SingleInstance"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = var.instance_type
  }

  # Attach service role
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.beanstalk_service_role.name
  }

  # Inject SERVICE_URL pointing to the internal ALB DNS of the service environment on port 5183
  # Will be populated after service env is created/updated; Terraform will handle ordering via implicit reference
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "SERVICE_URL"
    # Use HTTP on default port 80; EB LB listens on 80 and proxies to app port internally
    value     = "http://${aws_elastic_beanstalk_environment.asgardeo_service_environment.cname}"
  }

  # Ensure app binds to expected internal port 5173 (EB proxy forwards from 80)
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "PORT"
    value     = "5173"
  }

  tags = local.tags
}

# Elastic Beanstalk Environment for time-service (LoadBalanced with internal ALB)
resource "aws_elastic_beanstalk_environment" "asgardeo_service_environment" {
  name                = "asgardeo-service-env"
  application         = aws_elastic_beanstalk_application.asgardeo_application.name
  solution_stack_name = "64bit Amazon Linux 2023 v6.6.6 running Node.js 22"
  version_label       = aws_elastic_beanstalk_application_version.service_app_version.name

  # Make this a load-balanced environment with internal ALB
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
  }

  # Ensure the Application Load Balancer is internal (private within the VPC)
  setting {
    namespace = "aws:elbv2:loadbalancer"
    name      = "Scheme"
    value     = "internal"
  }

  # Assign VPC and subnets
  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.asgardeo_vpc.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", [for s in aws_subnet.public : s.id])
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = join(",", [for s in aws_subnet.public : s.id])
  }

  # Security groups: instances and ALB
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.service_instance_sg.id
  }

  setting {
    namespace = "aws:elbv2:loadbalancer"
    name      = "SecurityGroups"
    value     = aws_security_group.service_elb_sg.id
  }

  # Instance profile and type
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.beanstalk_ec2_profile.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = var.instance_type
  }

  # Use default load balancer listener on port 80. Nginx on instances will proxy to app port.

  # Define EB application process and health check (AL2023 v6)
  setting {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "Port"
    value     = "5183"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "Protocol"
    value     = "HTTP"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "HealthCheckPath"
    value     = "/"
  }

  # Service role attachment
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.beanstalk_service_role.name
  }

  # Ensure service binds to expected internal port 5183
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "PORT"
    value     = "5183"
  }

  tags = merge(local.tags, { Role = "time-service" })
}
