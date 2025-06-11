terraform {
  required_version = ">= 1.6"
  backend "s3" {
    bucket         = "acme-mc-tfstate"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "acme-mc-tf-lock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}


# networking

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default_public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

resource "aws_security_group" "mc" {
  name_prefix = "mc-sg-${var.environment}-"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Minecraft"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "NFS for EFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# efs storage

resource "aws_efs_file_system" "mc" {
  encrypted = true
  throughput_mode = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
}

resource "aws_efs_mount_target" "mc" {
  for_each        = toset(data.aws_subnets.default_public.ids)
  file_system_id  = aws_efs_file_system.mc.id
  subnet_id       = each.value
  security_groups = [aws_security_group.mc.id]
}

# fargate + ECS

resource "aws_ecs_cluster" "mc" {
  name = "mc-cluster-${var.environment}"
}

resource "aws_ecs_task_definition" "mc" {
  family                   = "mc-task-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory

  container_definitions = jsonencode([{
    name  = "minecraft"
    image = "itzg/minecraft-server:java21"
    environment = [
      { name = "EULA", value = "TRUE" }
    ]
    portMappings = [{ containerPort = 25565, protocol = "tcp" }]
    mountPoints  = [{ sourceVolume = "mc-data", containerPath = "/data" }]
    healthCheck = {
      command     = ["CMD-SHELL", "nc -z localhost 25565"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])

  volume {
    name = "mc-data"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.mc.id
      transit_encryption = "ENABLED"
      root_directory = "/"
    }
  }
}

resource "aws_ecs_service" "mc" {
  name            = "mc-service-${var.environment}"
  cluster         = aws_ecs_cluster.mc.id
  task_definition = aws_ecs_task_definition.mc.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default_public.ids
    security_groups  = [aws_security_group.mc.id]
    assign_public_ip = true
  }

  depends_on = [aws_efs_mount_target.mc]
}

# outputs for smoke-test

output "ecs_cluster_name" {
  value = aws_ecs_cluster.mc.name
}

output "service_name" {
  value = aws_ecs_service.mc.name
}
