# DevOps Pipeline to Deploy Webapp to AWS Elastic Beanstalk

## Project Overview
A CI/CD pipeline to automatically deploy a web application to AWS Elastic Beanstalk. This is a demo/POC environment focused on simplicity over production readiness.

## Architecture Overview
- **Source of webapp**: A GitHub repository provided by partner team.
- **Infrastructure as Code**: Terraform
- **Deployment Target**: AWS Elastic Beanstalk (single instance)
- **Application Type**: Static HTML web application (no database required)

## Simplifications (POC Only)
- Single instance deployment (no auto-scaling)
- No database/backend services
- No custom domain (use Elastic Beanstalk provided URL)
- No SSL/HTTPS required
- No staging environments
- Basic security configurations

## Technology Stack
- **Infrastructure**: Terraform (latest stable version)
- **Cloud Provider**: AWS
- **Compute**: AWS Elastic Beanstalk
- **Version Control**: GitHub

## Terraform Infrastructure Components

### 1. VPC (Virtual Private Cloud)
- **Resource Type**: `aws_vpc`
- **Resource Name**: `asgardeo_vpc` (or similar)
- **Requirements**:
  - CIDR block: 10.0.0.0/16
  - Enable DNS hostnames and DNS support
  - Public subnets in at least 2 availability zones (Beanstalk requirement)
  - Internet Gateway for public internet access
  - Route table with route to Internet Gateway

### 2. Security Group
- **Resource Type**: `aws_security_group`
- **Resource Name**: `asgardeo_security_group` (or similar)
- **Requirements**:
  - Allow inbound HTTP traffic (port 80) from 0.0.0.0/0
  - Allow outbound traffic to all destinations (0.0.0.0/0)
  - Attached to Elastic Beanstalk environment

### 3. IAM Roles and Policies
- **Resource Types**: `aws_iam_role`, `aws_iam_instance_profile`, `aws_iam_role_policy_attachment`
- **Resource Names**: Use `asgardeo_*` prefix (e.g., `asgardeo_beanstalk_ec2_role`)
- **Requirements**:
  - EC2 instance profile for Beanstalk instances
  - Service role for Elastic Beanstalk
  - Attach AWS managed policies:
    - `AWSElasticBeanstalkWebTier`
    - `AWSElasticBeanstalkMulticontainerDocker` (if using Docker)
    - `AWSElasticBeanstalkWorkerTier` (if needed)

### 4. Elastic Beanstalk Application
- **Resource Type**: `aws_elastic_beanstalk_application`
- **Resource Name**: `asgardeo_application`
- **Requirements**:
  - Application name: "asgardeo-webapp-demo"
  - Description: "Demo application for Asgardeo"

### 5. Elastic Beanstalk Environment
- **Resource Type**: `aws_elastic_beanstalk_environment`
- **Resource Name**: `asgardeo_environment`
- **Requirements**:
  - Environment name: "asgardeo-webapp-demo-env"
  - Solution stack: Use latest supported platform for web application
    - For Node.js: "64bit Amazon Linux 2023 v6.x.x running Node.js 22"
  - Instance type: t3.micro (free tier eligible)
  - Single instance deployment (no load balancer for simplicity)
  - Configuration settings:
    - VPC ID
    - Subnet IDs (public subnets)
    - Security group
    - IAM instance profile
    - Environment type: SingleInstance

### 6. Application Version Deployment
- **Resource Type**: `aws_elastic_beanstalk_application_version`
- **Resource Name**: `asgardeo_app_version`
- **Requirements**:
  - S3 bucket to store application bundle (name: "asgardeo-webapp-artifacts" or similar)
  - Upload application bundle (.zip of webapp files)
  - Associate with Beanstalk application
  - Deploy to environment

## CI/CD Pipeline Requirements (GitHub Actions)

### Workflow Triggers
- Push to `main` branch
- Manual workflow dispatch (for testing)

### Workflow Steps
1. **Checkout Code**: Checkout the repository
2. **Setup Terraform**: Install Terraform CLI
3. **Configure AWS Credentials**: Use GitHub Secrets for AWS access
4. **Terraform Init**: Initialize Terraform working directory
5. **Terraform Plan**: Preview infrastructure changes
6. **Terraform Apply**: Apply infrastructure changes (auto-approve for POC)
7. **Package Application**: Create .zip bundle of webapp files
8. **Upload to S3**: Upload application bundle to S3
9. **Deploy to Beanstalk**: Create/update application version and deploy
10. **Output URL**: Display Elastic Beanstalk environment URL
11. **Health Check**: Verify application is accessible (curl the homepage)

## Required GitHub Secrets
- `AWS_ACCESS_KEY_ID`: AWS IAM user access key
- `AWS_SECRET_ACCESS_KEY`: AWS IAM user secret key
- `AWS_REGION`: us-east-1
- `AWS_ACCOUNT_ID`: AWS account ID (optional, for S3 bucket naming)  <- XXXX decide what account to use

## Terraform Variables

### Required Variables
- `aws_region` (string): us-east-1
- `project_name` (string): webapp-demo
- `environment` (string): Asgardeo-demo

### Optional Variables
- `instance_type` t3.micro
- `availability_zones` auto-detect 2 AZs

## Outputs
- `beanstalk_environment_url`: The URL of the deployed application
- `beanstalk_environment_id`: The environment ID
- `vpc_id`: The VPC ID created
- `application_version`: The deployed application version

## Testing Requirements

### Manual Testing
1. Run `terraform apply` locally to provision infrastructure
2. Access the Beanstalk URL in a browser
3. Verify the homepage loads successfully
4. Check AWS Console for resource creation

### Automated Testing
1. GitHub Actions workflow should complete without errors
2. HTTP health check should return 200 status code
3. Homepage content should be served

## Cleanup/Destroy
- Provide script or documentation to run `terraform destroy`
- Ensure all AWS resources are removed to avoid charges
- S3 bucket with application versions may need manual cleanup

## Sample Application
Include a minimal `index.html` for initial testing:


## Deployment Test Harness

Three ways to test that Terraform can deploy the sample web app into your AWS account:

### Option A-1: test Terraform works independant of Git
Prerequisites:
- Terraform installed
- AWS credentials in your environment (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION)

Steps:
1. zip files in webapp directory and put in parent directory: zip -r webapp.zip webapp/
2. cd to terraform directory
3. terraform init/plan/apply
4. go to the url displayed in the terraform output to see app working
5. terraform destroy

### Option A: Local test script (recommended for quick validation)
Prerequisites:
- Terraform installed
- AWS credentials in your environment (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION)
- Optional: jq installed

Steps:
1. Run the test script:
   - Default (deploy, wait for 200 OK, then destroy):
     - bash scripts/test_deploy.sh
   - Keep resources for inspection (remember to destroy later):
     - SKIP_DESTROY=1 bash scripts/test_deploy.sh
   - Customize variables (examples):
     - TF_VAR_project_name=myproj TF_VAR_environment=dev bash scripts/test_deploy.sh
2. The script will:
   - terraform init/plan/apply in the terraform/ folder
   - fetch the Beanstalk environment URL from outputs
   - poll the URL until HTTP 200 (up to ~15 minutes)
   - destroy resources by default to avoid charges

Environment toggles:
- SKIP_DESTROY=1 to keep resources
- MAX_WAIT_SECONDS and SLEEP_SECONDS to tune health-check wait
- TF_VAR_* to set Terraform variables (e.g., TF_VAR_aws_region)

### Option B: GitHub Actions (manual trigger)
A workflow is provided to run the same test in CI using your AWS credentials and region.

- Workflow: .github/workflows/test-deploy.yml
- Triggers: workflow_dispatch (manual)
- Required GitHub Secrets:
  - AWS_ACCESS_KEY_ID
  - AWS_SECRET_ACCESS_KEY
  - (Optional) AWS_REGION if not provided as an input

How to run:
1. Push this repository to GitHub and configure the secrets above.
2. In the Actions tab, run "Test Terraform Deploy".
3. Inputs:
   - aws_region: defaults to us-east-1
   - skip_destroy: default false (will destroy after test)
4. The job will provision, wait for HTTP 200, and destroy by default.

Notes on costs and cleanup:
- The test script/workflow destroys by default. If you skip destroy, ensure you run scripts/destroy.sh or terraform destroy in terraform/ afterward to avoid charges.
- S3 artifact buckets with versioning may retain versions; empty and delete as needed.
