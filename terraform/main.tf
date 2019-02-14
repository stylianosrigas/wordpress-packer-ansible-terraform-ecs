provider "aws" {
  region = "${var.region}"
  access_key = ""
  secret_key = ""
}

################################################################################
# ECS execution role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-execution-role"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# ECS execution policy
resource "aws_iam_policy" "ecs_task_execution_policy" {
  name = "ecs-execution-policy"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
    {
        "Effect": "Allow",
        "Action": [
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

# Attach execution policy to execution role
resource "aws_iam_role_policy_attachment" "ecs-role-attach" {
    role       = "${aws_iam_role.ecs_task_execution_role.name}"
    policy_arn = "${aws_iam_policy.ecs_task_execution_policy.arn}"
}

################################################################################

# ECR repository creation
resource "aws_ecr_repository" "directory" {
  name = "wordpress-directory"
}

# ECS Cluster creation
resource "aws_ecs_cluster" "main" {
  name = "wordpress-fargate-cluster"
}

# ECS Task Definition creation
resource "aws_ecs_task_definition" "task" {
  family                   = "wordpress"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "${var.fargate_cpu}"
  memory                   = "${var.fargate_memory}"
  task_role_arn            = "${aws_iam_role.ecs_task_execution_role.arn}"
  execution_role_arn       = "${aws_iam_role.ecs_task_execution_role.arn}"

  container_definitions = <<DEFINITION
[
  {
    "cpu": ${var.fargate_cpu},
    "image": "${aws_ecr_repository.directory.repository_url}:${var.docker_image}",
    "memory": ${var.fargate_memory},
    "name": "app",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": ${var.app_port},
        "hostPort": ${var.app_port}
      }
    ]
  }
]
DEFINITION
}

# ECS service SG creation
resource "aws_security_group" "ecs_tasks" {
  name        = "wordpress-ecs-sg"
  description = "Allow inbound access in port 80 only"
  vpc_id      = "${var.vpc_id}"

  ingress {
    protocol        = "tcp"
    from_port       = "${var.app_port}"
    to_port         = "${var.app_port}"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS service creation
resource "aws_ecs_service" "main" {
  name            = "wordpress-ecs-service"
  cluster         = "${aws_ecs_cluster.main.id}"
  task_definition = "${aws_ecs_task_definition.task.arn}"
  desired_count   = "${var.task_count}"
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = ["${aws_security_group.ecs_tasks.id}"]
    subnets          = ["${var.subnets}"]
    assign_public_ip = "True"
  }
}

################################################################################
# RDS Security group
resource "aws_security_group" "rds" {
  name        = "wordpress-rds-sg"
  description = "Allow inbound access in port 3306 only"
  vpc_id      = "${var.vpc_id}"

  ingress {
    protocol        = "tcp"
    from_port       = "${var.db_port}"
    to_port         = "${var.db_port}"
    security_groups = ["${aws_security_group.ecs_tasks.id}"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS DB Subnet Group
resource "aws_db_subnet_group" "default" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = ["${var.subnets}"]
}

# The RDS Database used by Wordpress application
resource "aws_db_instance" "default" {
  allocated_storage      = "${var.db_storage}"
  storage_type           = "gp2"
  engine                 = "mariadb"
  engine_version         = "10.1.34"
  instance_class         = "${var.db_instance}"
  name                   = "${var.db_name}"
  username               = "${var.db_username}"
  password               = "${var.db_password}"
  parameter_group_name   = "default.mariadb10.1"
  vpc_security_group_ids = ["${aws_security_group.rds.id}"]
  db_subnet_group_name   = "${aws_db_subnet_group.default.name}"
  skip_final_snapshot    = "True"
}
