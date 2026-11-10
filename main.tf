# Separate state: ECR must exist before a Docker image can be pushed.
resource "aws_ecr_repository" "website" {
  name                 = "morays-ecs-website"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # Lab only: destroys images when this repository is destroyed.

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "keep_recent" {
  repository = aws_ecr_repository.website.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Retain the latest 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
