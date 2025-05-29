# Configure the AWS Provider
terraform {
  required_version = ">= 1.2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Configuration
resource "aws_vpc" "prefect_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "prefect-ecs"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "prefect_igw" {
  vpc_id = aws_vpc.prefect_vpc.id

  tags = {
    Name = "prefect-ecs"
  }
}

# Public Subnets
resource "aws_subnet" "public_subnets" {
  count             = 3
  vpc_id            = aws_vpc.prefect_vpc.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  
  map_public_ip_on_launch = true

  tags = {
    Name = "prefect-ecs-public-${count.index + 1}"
    Type = "Public"
  }
}

# Private Subnets
resource "aws_subnet" "private_subnets" {
  count             = 3
  vpc_id            = aws_vpc.prefect_vpc.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "prefect-ecs-private-${count.index + 1}"
    Type = "Private"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  
  tags = {
    Name = "prefect-ecs"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "prefect_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnets[0].id

  tags = {
    Name = "prefect-ecs"
  }

  depends_on = [aws_internet_gateway.prefect_igw]
}

# Route Table for Public Subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.prefect_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.prefect_igw.id
  }

  tags = {
    Name = "prefect-ecs-public"
  }
}

# Route Table for Private Subnets
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.prefect_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.prefect_nat.id
  }

  tags = {
    Name = "prefect-ecs-private"
  }
}

# Associate Public Subnets with Public Route Table
resource "aws_route_table_association" "public_subnet_associations" {
  count          = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Associate Private Subnets with Private Route Table
resource "aws_route_table_association" "private_subnet_associations" {
  count          = 3
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_tasks_sg" {
  name        = "prefect-ecs-tasks"
  description = "Security group for Prefect ECS tasks"
  vpc_id      = aws_vpc.prefect_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "prefect-ecs"
  }
}

# AWS Secrets Manager Secret for Prefect API Key
resource "aws_secretsmanager_secret" "prefect_api_key" {
  name                    = "prefect-api-key"
  description             = "Prefect Cloud API Key"
  recovery_window_in_days = 0  # For immediate deletion in dev

  tags = {
    Name = "prefect-ecs"
  }
}

resource "aws_secretsmanager_secret_version" "prefect_api_key_version" {
  secret_id     = aws_secretsmanager_secret.prefect_api_key.id
  secret_string = var.prefect_api_key
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "prefect_task_execution_role" {
  name = "prefect-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "prefect-ecs"
  }
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "task_execution_role_policy" {
  role       = aws_iam_role.prefect_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Custom policy for accessing Secrets Manager
resource "aws_iam_policy" "secrets_manager_policy" {
  name        = "prefect-secrets-manager-policy"
  description = "Policy to allow access to Prefect API key in Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.prefect_api_key.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_manager_policy_attachment" {
  role       = aws_iam_role.prefect_task_execution_role.name
  policy_arn = aws_iam_policy.secrets_manager_policy.arn
}

# ECS Cluster
resource "aws_ecs_cluster" "prefect_cluster" {
  name = "prefect-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "prefect-ecs"
  }
}

# Service Discovery Namespace
resource "aws_service_discovery_private_dns_namespace" "prefect_namespace" {
  name        = "default.prefect.local"
  description = "Private DNS namespace for Prefect services"
  vpc         = aws_vpc.prefect_vpc.id

  tags = {
    Name = "prefect-ecs"
  }
}

# CloudWatch Log Group for ECS Tasks
resource "aws_cloudwatch_log_group" "prefect_worker_logs" {
  name              = "/ecs/prefect-worker"
  retention_in_days = 7

  tags = {
    Name = "prefect-ecs"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "prefect_worker" {
  family                   = "prefect-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.prefect_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "prefect-worker"
      image = var.prefect_image
      
      environment = [
        {
          name  = "PREFECT_API_URL"
          value = var.prefect_api_url
        },
        {
          name  = "PREFECT_ACCOUNT_ID"
          value = var.prefect_account_id
        },
        {
          name  = "PREFECT_WORKSPACE_ID"
          value = var.prefect_workspace_id
        }
      ]

      secrets = [
        {
          name      = "PREFECT_API_KEY"
          valueFrom = aws_secretsmanager_secret.prefect_api_key.arn
        }
      ]

      command = [
        "prefect", "worker", "start",
        "--pool", var.work_pool_name,
        "--name", "dev-worker"
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.prefect_worker_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      essential = true
    }
  ])

  tags = {
    Name = "prefect-ecs"
  }
}

# ECS Service
resource "aws_ecs_service" "prefect_worker_service" {
  name            = "prefect-worker-service"
  cluster         = aws_ecs_cluster.prefect_cluster.id
  task_definition = aws_ecs_task_definition.prefect_worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private_subnets[*].id
    security_groups  = [aws_security_group.ecs_tasks_sg.id]
    assign_public_ip = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.task_execution_role_policy,
    aws_iam_role_policy_attachment.secrets_manager_policy_attachment
  ]

  tags = {
    Name = "prefect-ecs"
  }
}