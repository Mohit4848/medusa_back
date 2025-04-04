# AWS Provider Configuration
provider "aws" {
  region = "us-east-1"
}


# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.app_name}-vpc-${var.app_environment}"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.app_name}-public-subnet-${var.app_environment}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.app_name}-igw-${var.app_environment}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.app_name}-public-rt-${var.app_environment}"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "ecs_sg" {
  name        = "${var.app_name}-sg-${var.app_environment}"
  description = "Allow inbound traffic for Medusa"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 9000 # Default Medusa port
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Ideally restrict to your IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-sg-${var.app_environment}"
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.app_name}-execution-role-${var.app_environment}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# EC2 Launch Template
resource "aws_launch_template" "ecs_lt" {
  name_prefix   = "${var.app_name}-lt-${var.app_environment}"
  image_id      = "ami-084568db4383264d4" # Ubuntu 22.04 LTS in us-east-1
  instance_type = var.ec2_instance_type
  
  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io awscli
    systemctl start docker
    systemctl enable docker

    # Install ECS agent
    mkdir -p /etc/ecs
    echo "ECS_CLUSTER=medusa-backend-cluster-dev" >> /etc/ecs/ecs.config
    echo "ECS_AVAILABLE_LOGGING_DRIVERS=[\"json-file\",\"awslogs\"]" >> /etc/ecs/ecs.config

    # Install ECS agent from Docker hub
    docker pull amazon/amazon-ecs-agent:latest
    docker run --name ecs-agent \
      --detach=true \
      --restart=on-failure:10 \
      --volume=/var/run:/var/run \
      --volume=/var/log/ecs/:/log \
      --volume=/var/lib/ecs/data:/data \
      --volume=/etc/ecs:/etc/ecs \
      --volume=/etc/ecs:/var/lib/ecs/config \
      --net=host \
      --env-file=/etc/ecs/ecs.config \
      amazon/amazon-ecs-agent:latest
  EOF
  )
  
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ecs_sg.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.app_name}-ecs-instance-${var.app_environment}"
    }
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster-${var.app_environment}"
}

# Auto Scaling Group for ECS
resource "aws_autoscaling_group" "ecs_asg" {
  name                = "${var.app_name}-asg-${var.app_environment}"
  vpc_zone_identifier = [aws_subnet.public.id]
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  
  launch_template {
    id      = aws_launch_template.ecs_lt.id
    version = "$Latest"
  }
  
  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

# ECS Capacity Provider
resource "aws_ecs_capacity_provider" "ec2" {
  name = "${var.app_name}-capacity-provider-${var.app_environment}"
  
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn
    
    managed_scaling {
      maximum_scaling_step_size = 1
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = [aws_ecs_capacity_provider.ec2.name]
  
  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "medusa" {
  family                   = "${var.app_name}-task-${var.app_environment}"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  
  container_definitions = jsonencode([
    {
      name      = "${var.app_name}-container"
      image     = "${var.dockerhub_username}/medusa-backend:latest"
      essential = true
      memory    = 700
      portMappings = [
        {
          containerPort = 9000
          hostPort      = 9000
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "NODE_ENV",
          value = "production"
        },
        {
          name  = "PORT",
          value = "9000"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.app_name}-${var.app_environment}"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.app_name}-${var.app_environment}"
  retention_in_days = 7 # Keep logs for 7 days to stay within free tier
}

# ECS Service
resource "aws_ecs_service" "medusa" {
  name            = "${var.app_name}-service-${var.app_environment}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.medusa.arn
  desired_count   = 1
  
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
  }
}

# Output the public IP of the EC2 instance
output "public_ip" {
  value = "Access Medusa at: http://<EC2_PUBLIC_IP>:9000"
  description = "URL to access the Medusa backend"
}
