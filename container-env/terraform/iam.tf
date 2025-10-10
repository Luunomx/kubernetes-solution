resource "aws_iam_role" "swarm_ec2_role" {
  name = "SwarmEC2Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "swarm_ec2_ecr_readonly" {
  role       = aws_iam_role.swarm_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "swarm_ec2_profile" {
  name = "EC2SwarmInstanceProfile"
  role = aws_iam_role.swarm_ec2_role.name
}
