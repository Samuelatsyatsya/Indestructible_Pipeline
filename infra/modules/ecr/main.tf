resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name = each.key

  # IMMUTABLE: a pushed tag can never be overwritten — guarantees artifact integrity.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    # Belt-and-suspenders: ECR also scans on push alongside Trivy in the pipeline.
    scan_on_push = true
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
