terraform {
  required_version = ">= 1.3.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.34.0"
    }
  }
}

provider "aws" {
  region = af-south-1
  default_tags {
    tags = module.tagging.data
  }
}

# VPC
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
}

# subnets
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-1a"
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-1a"
}

resource "aws_subnet" "data_subnet" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-west-1b"
}

# target group
resource "aws_lb_target_group" "my_target_group" {
  name        = "target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    path                = "/"
    matcher             = "200"
  }
}

# Modify ELB resource to include target group
resource "aws_elb" "elb" {
  name               = "elb"
  availability_zones = ["us-west-1a", "us-west-1b"]
  
  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }
  
  listener {
    instance_port      = 443
    instance_protocol  = "HTTPS"
    lb_port            = 443
    lb_protocol        = "HTTPS"
    ssl_certificate_id = aws_acm_certificate.my_ssl_cert.arn
  }

  # Associate target group with the HTTPS listener
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

}

# EC2 instance
resource "aws_instance" "instance" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_subnet.id
  user_data              = <<-EOF
                              #!/bin/bash
                              yum install -y nginx
                              systemctl start nginx
                              EOF
  # Define Security Group allowing traffic from ELB
  security_groups        = [aws_security_group.elb_sg.name]
}

# Attach EC2 instance to the target group
resource "aws_lb_target_group_attachment" "instance_attachment" {
  target_group_arn = aws_lb_target_group.my_target_group.arn
  target_id        = aws_instance.instance.id
  port             = 80
}

# Security Group for ELB
resource "aws_security_group" "elb_sg" {
  vpc_id = aws_vpc.vpc.id

  # Allow HTTP and HTTPS inbound traffic
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
