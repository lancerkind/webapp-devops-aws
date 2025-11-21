# Specification for V2 Feature
The terraform infrastructure needs to be updated to support deployment of a webapplication that is coming from a different repository.
The webapp has incoming changes for this infrastructure to accommodate for the V2 version.  These changes will impact main.tf, deploy.yml, and deploy-from-web.yml.

Here are the changes I want to have implemented:
One elastic beanstalk application (named asgardeo-webapp-demo) will be used to host the webapp in one environment, and the time-service in another environment.  

# Changes to the webapp
The terraform infrastructure code has already been created but needs to be updated to support: 
- asgardeo-webapp-demo-env will have its own security group.
- The webapp will run on port 5173, accessible from the public internet. 
- The webapp is now dependant on a service called 'time-service'
- To configure the webapp to use time-service, the webapp needs to know the URL of the time-service via environment 
variable SERVICE_URL. This environment variable will be set in the webapp's Elastic Beanstalk environment.


# Deploying the new time service
The time-service will be deployed into the same VPC and beanstalk application as webapp, but will have its own
Elastic Beanstalk environment. The environment name will be asgardeo-service-env.
The environments use the same instance type.  Time-service is strictly non-public.  So although asgardeo-service-env will 
have a public IP, it will have it's own security group that allow traffic from asgardeo-demo-env security group only.
- time-service will be deployed before the webapp as a separate ElasticBeanstalk environment which will allow the 
SERVICE_URL environment variable to be established and passed to the webapp via the ElasticBeanstalk environment configuration.  
- The SERVICE_URL is of the format of http://<host>:<port> based on the environment CNAME of the time-service.
- time-service is running on port 5183, an internal port for accepting connections from the webapp.
- time-service has a healthcheck endpoint at the path of / which returns 200 OK
- time-service is implemented in NodeJS and uses Express. It will be packaged as a zip file in the webapp repository in the "service" folder.

# Connectivity
Both the webapp and time-service are Node.js/Express apps that listen on their internal ports (5173 and 5183 respectively). 
Elastic Beanstalk will expose 5173 via its standard HTTP port (80). The service is not exposed to the public internet, so
the webapp will connect to it via SERVICE_URL and use http://...:5183.

# Webapplication repository
The webapp repository will have a directory called "webapp" which contains the Node.js web application, and a directory
called "service" which will contain the Node.js service.  The infrastructure code will be triggered by repository dispatch
and its workflows (deploy.yml, deploy-from-web.yml) will produce two zip artifacts: one for the webapp created by zipping the contents in
the webapp directory, one for time-service created by zipping the contents in the service directory 
(e.g., webapp-<sha>.zip and service-<sha>.zip). Both zips will be uploaded to the same S3 artifacts bucket and versioned 
using the same commit SHA. The service beanstalk environment uses the service zip; the webapp beanstalk environment uses the webapp zip.
Since the sha comes from the commit SHA of the webapp repository, both zips will re-created by the infrastructure 
whenever the webapp repository is updated.

# Elastic Beanstalk Lifecycles
It must be possible to deploy a new version of time-service while the webapp remains running. 
Deploying a new version of time-service is done by updating its application version in the existing environment 
(no environment recreation). The webapp uses the same SERVICE_URL across time-service deployments 
(as long as time-service environment is not destroyed). If the time-service environment is ever destroyed and 
recreated, a subsequent Terraform apply must also update the webapp environment so that SERVICE_URL points at the 
new CNAME.

## launching
nmp start will be used to launch the webapp.  And the same strategy will be used to launch the service.

# Other details
- use the current IAM role for both environments.
- scaling policy is SingleInstance.
- Terraform will use the same S3 remote backend and lock table for both beanstalk environments.
- Use the same EC2 instance type for both environments.
