variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnets" {
  type = list(string)
}

variable "key_name" {
  type    = string
  default = "" # lämna tomt om du inte vill sätta SSH-nyckel
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "manager_desired" {
  type    = number
  default = 1
}

variable "worker_desired" {
  type    = number
  default = 2
}

# Ubuntu 22.04 LTS (Jammy) – Canonical
data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Security Groups ---

resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP from internet"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Allow swarm traffic and SSH"
  vpc_id      = var.vpc_id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Swarm mgmt
  ingress {
    from_port   = 2377
    to_port     = 2377
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Swarm overlay
  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # App ports
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ec2-sg"
  }
}

# --- UserData (installerar Docker; Swarm init/join kan läggas till senare) ---
locals {
  docker_userdata = base64encode(<<-EOT
    #!/bin/bash
    set -eux
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker ubuntu || true
    systemctl enable --now docker
  EOT
  )
}

# --- Launch Templates ---
resource "aws_launch_template" "mgr_lt" {
  name_prefix   = "${var.project_name}-mgr-"
  image_id      = data.aws_ami.ubuntu_2204.id
  instance_type = var.instance_type
  key_name      = var.key_name != "" ? var.key_name : null
  user_data     = local.docker_userdata
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-mgr"
      Role = "swarm-manager"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_template" "wrk_lt" {
  name_prefix   = "${var.project_name}-wrk-"
  image_id      = data.aws_ami.ubuntu_2204.id
  instance_type = var.instance_type
  key_name      = var.key_name != "" ? var.key_name : null
  user_data     = local.docker_userdata
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-wrk"
      Role = "swarm-worker"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Auto Scaling Groups ---
resource "aws_autoscaling_group" "mgr_asg" {
  name                      = "${var.project_name}-mgr-asg"
  vpc_zone_identifier       = var.public_subnets
  desired_capacity          = var.manager_desired
  min_size                  = var.manager_desired
  max_size                  = var.manager_desired
  health_check_type         = "EC2"
  health_check_grace_period = 60

  launch_template {
    id      = aws_launch_template.mgr_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-mgr"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group" "wrk_asg" {
  name                      = "${var.project_name}-wrk-asg"
  vpc_zone_identifier       = var.public_subnets
  desired_capacity          = var.worker_desired
  min_size                  = var.worker_desired
  max_size                  = var.worker_desired
  health_check_type         = "EC2"
  health_check_grace_period = 60

  launch_template {
    id      = aws_launch_template.wrk_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-wrk"
    propagate_at_launch = true
  }
}

# --- Outputs ---
output "alb_sg_id"    { value = aws_security_group.alb_sg.id }
output "ec2_sg_id"    { value = aws_security_group.ec2_sg.id }
output "mgr_asg_name" { value = aws_autoscaling_group.mgr_asg.name }
output "wrk_asg_name" { value = aws_autoscaling_group.wrk_asg.name }
