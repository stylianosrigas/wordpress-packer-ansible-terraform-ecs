# Wordpress - Packer - Ansible - Terraform - ECS

## Intro

The code in this repo can be used to create a "ready to use" Wordpress image that is deployed in ECS and uses external RDS database.

## Requirements

* Locally installed:
  * Packer
  * Kindle
  * Terraform
* AWS account

## What have I done?

In order to create the Wordpress image and automate the deployment in AWS I used a number of tools and infrastructure components, which can be seen in more detail in the sections bellow.

<img src="https://image.prntscr.com/image/BU8Qh4RKTXuGTqjGiW2e2w.png" alt="Solution Design" width="400" height="400" />


#### Packer

Packer was used to provision the Docker image with Wordpress application and all additional components using Ansible for the configuration. Furthermore packer creates the Dockerfile and pushes the image to AWS ECR, where it will be ready to be used by AWS ECS.

#### Ansible

Ansible was used for the configuration of the Docker image and it manages the configuration of several components:

* Nginx setup
* PHP-FPM setup
* Supervisord setup
* Wordpress setup

In addition to that, Ansible handles the installation of all the packages needed for the application setup.

#### Terraform

Terraform was used for the deployment of the infrastructure. Terraform more specifically deploys:

* IAM Role
* IAM Policy
* ECR Repository
* ECS Cluster (Fargate)
* ECS Task Definition
* ECS Service
* EC2 Security Groups
* RDS MariaDB

### AWS

AWS was used as the cloud provider to run the Wordpress application. More specifically, the AWS ECS Fargate service was selected to host the container run and RDS MariaDB database for the Wordpress database. The Fargate service was selected to avoid server management. An ECS Service is created to make sure that the Wordpress container task will run with as low downtime as possible. No option for Load Balancing was made to cut cost.


## How to run it?

In order to run the solution several components need to be executed.
At the moment no CI solution is in place and the deployment has to be done manually.

There are two different modes available, one for local and one for AWS testing. The local mode requires preexistence of a MariaDB database.

Both modes will need update of the ***ansible/group_vars/all*** file, where the db_name, db_user, db_password and db_host variables need to be specified.

#### Local Mode

Considering that you want to test the Docker image locally and Ansible variables are configured the only thing needed is to update the ***local_repository*** variable in the ***local_wordpress.json*** file with the name you want tag you want to give to your docker image. The next step is to run the ***packer build local_wordpress.json*** command. This command will initiate packer and will output the docker image.

#### AWS Mode

If you want to run Wordpress in AWS, the first thing needed is to deploy the terraform templates. For Terraform documentation please have a look here https://www.terraform.io/docs/index.html.

A list of variables is used under ***terraform/variables.tf*** and feel free to update anything needed. The ones that must be updated are the DB name, DB password and DB username. Please make sure to use the same values as in the Ansible configuration step.

In addition to the variables, AWS Secret and AWS Access keys need to be added in the ***terraform/main.tf*** file, in the provider section.

After variables and keys are updated, the infrastructure can be deployed by running the **terraform init**, **terraform plan** and **terraform apply** commands from inside the terraform directory.

Once the terraform infrastructure is deployed in AWS the next step is to run packer. The variables in ***packer/aws_wordpress.json*** need to be updated with your own values and the next step is to run the ***packer build aws_wordpress.json*** command. This command will initiate packer and will upload the Docker image in ECR.

The ECS service that was deployed via Terraform will pick the latest image from ECR and run the container. The task is exposing a public ip, which can be used to access the Wordpress app.


## How does it work?

All the tools used were described in the previous steps but in more detail the Wordpress app is using Nginx (mostly as a proxy), the supervisord, which was selected for better management of the Nginx and php-fpm service and the MariaDB database, which is running externally in AWS. The way the ECS service was deployed, is that it always looks for the latest ECR Wordpress image and makes sure that there is always one task running.

## What problems did I face?

Some of the issues I have faced during the development include:
 * ECS task not running with STOPPED (CannotPullContainerError). The reason for this error is either that the task has no outbound connectivity to get the image (check SGs) or that the image name specified in the task is not matching the one in ECR.
 * ECS task not running with STOPPED error. The reason for that is most probably related with RDS connection issues.
 * Not able to hit Wordpress page. I faced this error when testing locally and the reason was the Wordpress database setup.

## Automation

The deployment of the infrastructure and the creation of the Docker image is fully automated but requires manual running of the scripts. Furthermore, there is no automated handling of the passwords, which means that the user has to update the configs with keys and passwords before any deployment. Improvements needed in this part and others will be discussed in the section below.

## Improvements

* Enable Load Balancing for the ECS service to improve High Availability and Scalability.
* Enable HTPPS to improve security.
* Make use of CI solution for automation of the deployment.
* Use password management service, such as the AWS Parameter Store for better password handling.
* Use Route53 for Database and Wordpress DNS.
* Use Cloudwatch for container and application logs .
* Split Terraform template in multiple templates and handle ECS setup after the packer run via CI. The reason for this is that, the deployment right now is done in the following way ECR->ECS->Packer run. Therefore, when ECS spins up the first task the image is not yet deployed, which will lead to an error and will take ~5-10 minutes for the second task to come up and for Wordpress to run successfully. The right process should be, Terraform deployment of ECR, packer run to create the Docker image, Terraform deployment of ECS service that will pick the new image instantly.
* Make use of a combination of Graphite and Grafana or Prometheus and Grafana for metrics and monitoring

With the abovementioned improvements the solution is more Production ready and has improved security. The current solution can be used as a base for application deployments that make use of the Packer, Ansible and Terraform tools.
