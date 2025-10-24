# ECR Repositories
resource "aws_ecr_repository" "backend" {
  name = "bulletinboard-backend"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "bulletinboard-backend"
  }
}

resource "aws_ecr_repository" "frontend" {
  name = "bulletinboard-frontend"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "bulletinboard-frontend"
  }
}
