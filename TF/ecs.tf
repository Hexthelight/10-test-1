# IAM Policy

data "aws_iam_policy_document" "ecs-tasks" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs-tasks-role" {
    name = "ecs-tasks-role"
    assume_role_policy = data.aws_iam_policy_document.ecs-tasks.json
}

resource "aws_iam_role_policy_attachment" "ecs_dynamo_policy_attachment" {
    role = aws_iam_role.ecs-tasks-role.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "ecs_ecr_policy_attachment" {
    role = aws_iam_role.ecs-tasks-role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Apache

resource "aws_ecs_cluster" "cluster-apache" {
    name = "Test-1-apache"
}

resource "aws_ecs_capacity_provider" "link-apache" {
    name = "Test-1-apache"

    auto_scaling_group_provider {
        auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn
    }
}

resource "aws_ecs_task_definition" "def-apache" {
    family = "Test-1-apache"
    execution_role_arn = aws_iam_role.ecs-tasks-role.arn
    container_definitions = jsonencode([
        {
            name = "apache-app"
            image = "204642395454.dkr.ecr.eu-west-3.amazonaws.com/container-rundown-ecs-nginx-test-1:latest"
            cpu = 512
            memory = 1024
            portMappings = [
                {
                    containerPort = 80
                    hostPort = 0
                }
            ]
        }
    ])
}

resource "aws_ecs_cluster_capacity_providers" "link-apache" {
    cluster_name = aws_ecs_cluster.cluster-apache.name
    capacity_providers = [aws_ecs_capacity_provider.link-apache.name]
}

resource "aws_ecs_service" "test-1-apache" {
    name = "Test-1-apache"
    cluster = aws_ecs_cluster.cluster-apache.id
    task_definition = aws_ecs_task_definition.def-apache.arn
    desired_count = 2

    load_balancer {
        target_group_arn = aws_lb_target_group.lb.arn
        container_name = "apache-app"
        container_port = "80"
    }

    depends_on = [ aws_ecs_task_definition.def-apache ]
}

resource "aws_lb" "lb" {
    name = "ECS-test"
    internal = false
    load_balancer_type = "application"
    security_groups = [ aws_security_group.sg.id ]
    subnets = [aws_subnet.main-1.id, aws_subnet.main-2.id]
}

resource "aws_lb_target_group" "lb" {
    name = "test-tg"
    port = "80"
    protocol = "HTTP"
    vpc_id = aws_vpc.main.id
}

resource "aws_lb_listener" "lb" {
    load_balancer_arn = aws_lb.lb.arn
    port = "80"
    protocol = "HTTP"

    default_action {
        type = "forward"
        target_group_arn = aws_lb_target_group.lb.arn
    }
}