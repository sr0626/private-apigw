# Test EC2 instance for validating the private API from inside the VPC.
# Commented out so it stays terminated. Uncomment this file (and the
# ec2_instance_id / ec2_public_ip outputs in outputs.tf) and run
# `terraform apply` to bring it back.

resource "aws_security_group" "ec2_sg" {
  name   = "private-api-test-ec2"
  vpc_id = var.vpc_id

  # No inbound SSH: access the instance via SSM Session Manager
  # (the instance has the AmazonSSMManagedInstanceCore role attached).

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

resource "aws_iam_role" "ec2_role" {
  name = "ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  role = aws_iam_role.ec2_role.name
  name = "ec2-ssm-profile"
}

resource "aws_instance" "test" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = var.subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  tags = {
    Name = "private-api-test"
  }
}
