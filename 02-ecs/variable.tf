variable "aws_region" {
  description = "Region for the ECS infrastructure; must match the ECR image Region."
  type        = string
  default     = "eu-west-2"
}

variable "project_name" {
  description = "Unique naming prefix for this learning environment."
  type        = string
  default     = "morays-ecs-demo"
}

variable "image_uri" {
  description = "FULL image URI including the tag, e.g. 123456789012.dkr.ecr.eu-west-2.amazonaws.com/morays-ecs-website:20261110."
  type        = string
  validation {
    condition     = length(trimspace(var.image_uri)) > 0
    error_message = "Set image_uri to an existing ECR image URL including a tag."
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.40.1.0/24", "10.40.2.0/24"]
  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Provide exactly two public subnet CIDRs."
  }
}

variable "desired_count" {
  description = "Number of Fargate tasks (1 minimises learning costs)."
  type        = number
  default     = 1
  validation {
    condition     = var.desired_count >= 1 && var.desired_count <= 10
    error_message = "Choose 1 through 10 tasks."
  }
}

