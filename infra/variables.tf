variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "ecs_cpu" {
  description = "Fargate CPU units"
  type        = number
  default     = 1024
}

variable "ecs_memory" {
  description = "Fargate Memory (MiB)"
  type        = number
  default     = 2048
}
