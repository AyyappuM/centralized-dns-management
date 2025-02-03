data "aws_availability_zones" "available" {}
data "aws_region" "current" {}

resource "aws_vpc" "my_vpc" {
  cidr_block = "192.168.2.0/24"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "my-vpc"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "192.168.2.0/25"
  availability_zone = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "private-subnet"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "private-route-table"
  }
}

# Associate the private subnet with the private route table
resource "aws_route_table_association" "aws_route_table_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_security_group" "allow_all_traffic" {
  name        = "allow-all-traffic"
  description = "Security group to allow all inbound and outbound traffic"
  vpc_id      = aws_vpc.my_vpc.id  # Attach this to the VPC created earlier

  # Allow all inbound traffic
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # "-1" means all protocols
    cidr_blocks = ["0.0.0.0/0"]  # Open to all IP addresses
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow-all-traffic"
  }
}

resource "aws_service_discovery_private_dns_namespace" "acc3_example_local" {
  name        = "acc3.example.local"
  description = "acc3.example.local"
  vpc         = aws_vpc.my_vpc.id
}

resource "aws_ecr_repository" "service_b_ecr_repository" {
  name = "service_b_ecr_repository"
  force_delete = true
}

output "service_b_ecr_repository_url" {
  value = aws_ecr_repository.service_b_ecr_repository.repository_url
}

resource "aws_ecs_cluster" "example" {
  name = "MyECSCluster"
}

# ECS TASK ROLE

resource "aws_iam_role" "ECSTaskRole" {
  name                = "ECS_Task_Role"
  assume_role_policy  = file("${path.module}/assume-role-policy.json")
}

resource "aws_iam_policy" "ECSTaskRolePermissionsPolicy" {
  name        = "ECS_Task_Role_Permission_Policy"
  policy      = file("${path.module}/ecs-task-role-permission-policy.json")
}

resource "aws_iam_role_policy_attachment" "ecs-task-role-customer-permission-policy-attachment" {
  role       = aws_iam_role.ECSTaskRole.name
  policy_arn = "${aws_iam_policy.ECSTaskRolePermissionsPolicy.arn}"
}

data "aws_iam_policy" "AWSAppMeshEnvoyAccess_Managed_Policy" {
  arn = "arn:aws:iam::aws:policy/AWSAppMeshEnvoyAccess"
}

resource "aws_iam_role_policy_attachment" "ecs-task-role-AWSAppMeshEnvoyAccess-managed-policy-attachment" {
  role       = aws_iam_role.ECSTaskRole.name
  policy_arn = "${data.aws_iam_policy.AWSAppMeshEnvoyAccess_Managed_Policy.arn}"
}

# ECS TASK EXECUTION ROLE

resource "aws_iam_role" "ECSTaskExecutionRole" {
  name                = "ECS_Task_Execution_Role"
  assume_role_policy  = file("${path.module}/assume-role-policy.json")
}

resource "aws_iam_policy" "ECSTaskExecutionRolePermissionsPolicy" {
  name        = "ECS_Task_Execution_Role_Permission_Policy"
  policy      = file("${path.module}/ecs-task-execution-role-permission-policy.json")
}

resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-customer-permission-policy-attachment" {
  role       = aws_iam_role.ECSTaskExecutionRole.name
  policy_arn = "${aws_iam_policy.ECSTaskExecutionRolePermissionsPolicy.arn}"
}

data "aws_iam_policy" "AmazonECSTaskExecutionRolePolicy_Managed_Policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs-task-role-AmazonECSTaskExecutionRolePolicy-managed-policy-attachment" {
  role       = aws_iam_role.ECSTaskExecutionRole.name
  policy_arn = "${data.aws_iam_policy.AmazonECSTaskExecutionRolePolicy_Managed_Policy.arn}"
}

# ECS TASK DEFINITION

resource "aws_ecs_task_definition" "ecs_service" {
  family                   = "serviceb"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  memory = 2048
  cpu = 1024  
  execution_role_arn = aws_iam_role.ECSTaskExecutionRole.arn
  task_role_arn = aws_iam_role.ECSTaskRole.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = templatefile("${path.module}/container_definitions.json", {
    service_b_ecr_repository_url = aws_ecr_repository.service_b_ecr_repository.repository_url
    region = data.aws_region.current.name
  })
}

# ECS SERVICE

resource "aws_ecs_service" "serviceb" {
  name = "serviceb"
  cluster         = aws_ecs_cluster.example.id
  task_definition = aws_ecs_task_definition.ecs_service.arn
  desired_count   = 1
  enable_execute_command = true
  #force_new_deployment = false

  network_configuration {
    security_groups  = ["${aws_security_group.allow_all_traffic.id}"]
    subnets          = ["${aws_subnet.private_subnet.id}"]
    assign_public_ip = true
  }

  capacity_provider_strategy {
    base              = 1
    capacity_provider = "FARGATE"
    weight            = 100
  }

  service_registries {
    registry_arn = aws_service_discovery_service.example.arn
  }
}

resource "aws_service_discovery_service" "example" {
  name = "serviceb"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.acc3_example_local.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }
}

# DEPLOY PRIVATE LINKS

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id            = aws_vpc.my_vpc.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type = "Interface"
  subnet_ids        = ["${aws_subnet.private_subnet.id}"]
  security_group_ids = ["${aws_security_group.allow_all_traffic.id}"]

  private_dns_enabled = true
  tags = {
    Name = "ECR API VPC Endpoint"
  }
}

resource "aws_vpc_endpoint" "ecr_docker" {
  vpc_id            = aws_vpc.my_vpc.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr" # ECR Docker
  vpc_endpoint_type = "Interface"
  subnet_ids        = ["${aws_subnet.private_subnet.id}"]
  security_group_ids = ["${aws_security_group.allow_all_traffic.id}"]

  private_dns_enabled = true
  tags = {
    Name = "ECR Docker VPC Endpoint"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.my_vpc.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3" # S3 Gateway
  vpc_endpoint_type = "Gateway"
  route_table_ids   = ["${aws_route_table.private_route_table.id}"]

  tags = {
    Name = "S3 Gateway VPC Endpoint"
  }
}

resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id            = aws_vpc.my_vpc.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.logs" # CloudWatch Logs
  vpc_endpoint_type = "Interface"
  subnet_ids        = ["${aws_subnet.private_subnet.id}"]
  security_group_ids = ["${aws_security_group.allow_all_traffic.id}"]

  private_dns_enabled = true
  tags = {
    Name = "CloudWatch Logs VPC Endpoint"
  }
}