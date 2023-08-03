# Retrieve AMI

data "aws_ami" "amazon-linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }
  owners = ["amazon"]
}

# VPC Creation

resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"

    tags = {
        Name = "main"
    }
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.main.id

    tags = {
        Name = "main"
    }
}

resource "aws_route_table" "route" {
    vpc_id = aws_vpc.main.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
}

resource "aws_route_table_association" "association-1" {
    subnet_id = aws_subnet.main-1.id
    route_table_id = aws_route_table.route.id
}

resource "aws_route_table_association" "association-2" {
    subnet_id = aws_subnet.main-2.id
    route_table_id = aws_route_table.route.id
}


resource "aws_subnet" "main-1" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "eu-west-3a"
    map_public_ip_on_launch = true

    tags = {
        Name = "main"
    }
}

resource "aws_subnet" "main-2" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "eu-west-3b"
  map_public_ip_on_launch = true
}

resource "aws_security_group" "sg" {
    name = "sg"
    vpc_id = aws_vpc.main.id

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
      from_port = 32768
      to_port = 65535
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

# IAM policies

data "aws_iam_policy_document" "ecs_agent" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_agent" {
  name               = "ecs-agent"
  assume_role_policy = data.aws_iam_policy_document.ecs_agent.json
}


resource "aws_iam_role_policy_attachment" "ecs_agent" {
  role       = aws_iam_role.ecs_agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_agent" {
  name = "ecs-agent"
  role = aws_iam_role.ecs_agent.name
}

# EC2 autoscaling

resource "aws_launch_configuration" "ECS_launch_config" {
    image_id = data.aws_ami.amazon-linux.id
    instance_type = "t3.medium"

    security_groups = [aws_security_group.sg.id]
    iam_instance_profile = aws_iam_instance_profile.ecs_agent.name

    user_data = <<EOF
    #!/bin/bash
    yum update -y
    yum install ec2-instance-connect yum-utils
    amazon-linux-extras disable docker
    amazon-linux-extras install -y ecs; systemctl enable --now  --no-block ecs.service
    echo ECS_CLUSTER=${aws_ecs_cluster.cluster-apache.name} >> /etc/ecs/ecs.config
    EOF

    depends_on = [ aws_ecs_cluster.cluster-apache ]
}

resource "aws_autoscaling_group" "ecs_asg" {
    name = "ecs_asg"
    vpc_zone_identifier = [aws_subnet.main-1.id]
    launch_configuration = aws_launch_configuration.ECS_launch_config.name

    desired_capacity = 1
    min_size = 1
    max_size = 2
    health_check_grace_period = 300
    health_check_type = "EC2"
}

resource "aws_ec2_instance_connect_endpoint" "endpoint" {
    security_group_ids = [aws_security_group.sg.id]
    subnet_id = aws_subnet.main-1.id
}