data "aws_availability_zones" "available" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

variable "hub_account_id" {
  type        = string
}

variable "spoke_account_b_id" {
  type        = string
}

variable "aws_ram_resource_share_arn" {
  type = string
}

variable "dns_vpc_id" {
  type = string
}

resource "aws_vpc" "my_vpc" {
  cidr_block = "192.168.1.0/24"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "my-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "192.168.1.0/25"
  availability_zone = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "my-internet-gateway"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  route {
    cidr_block = "192.168.0.0/16"
    gateway_id = var.transit_gateway_id
  }

  depends_on = [ "aws_ec2_transit_gateway_vpc_attachment.example" ]

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "aws_route_table_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_security_group" "allow_all_traffic" {
  name        = "allow-all-traffic"
  description = "Security group to allow all inbound and outbound traffic"
  vpc_id      = aws_vpc.my_vpc.id  # Attach this to the VPC created earlier

  # Allow all inbound traffic
  ingress {
    from_port   = 8080
    to_port     = 8080
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

  tags = {
    Name = "allow-all-traffic"
  }
}

resource "aws_service_discovery_private_dns_namespace" "acc2_example_local" {
  name        = "acc2.example.local"
  description = "acc2.example.local"
  vpc         = aws_vpc.my_vpc.id
}

output "account_a_private_hosted_zone_id" {
  value = aws_service_discovery_private_dns_namespace.acc2_example_local.hosted_zone
}

resource "aws_ecr_repository" "service_a_ecr_repository" {
  name = "service_a_ecr_repository"
  force_delete = true
}

output "service_a_ecr_repository_url" {
  value = aws_ecr_repository.service_a_ecr_repository.repository_url
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
  family                   = "servicea"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # APPMESH proxy configuration is only supported in networkMode=awsvpc
  memory = 2048
  cpu = 1024  
  execution_role_arn = aws_iam_role.ECSTaskExecutionRole.arn
  task_role_arn = aws_iam_role.ECSTaskRole.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = templatefile("${path.module}/container_definitions.json", {
    service_a_ecr_repository_url = aws_ecr_repository.service_a_ecr_repository.repository_url
    region = data.aws_region.current.name
  })
}

# ECS SERVICE

resource "aws_ecs_service" "servicea" {
  name = "servicea"
  cluster         = aws_ecs_cluster.example.id
  task_definition = aws_ecs_task_definition.ecs_service.arn
  desired_count   = 1
  enable_execute_command = true
  #force_new_deployment = false

  network_configuration {
    security_groups  = ["${aws_security_group.allow_all_traffic.id}"]
    subnets          = ["${aws_subnet.public_subnet.id}"]
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
  name = "servicea"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.acc2_example_local.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }
}

resource "aws_ram_resource_share_accepter" "spoke_account_a_receiver_accept" {
  share_arn = var.aws_ram_resource_share_arn
}

# HOSTED ZONE & VPC ASSOCIATION AUTHORIZATION

resource "aws_route53_vpc_association_authorization" "private_hz_in_spoke_account_a_dns_vpc_in_hub_account_association_authorization" {
  vpc_id  = var.dns_vpc_id
  zone_id = aws_service_discovery_private_dns_namespace.acc2_example_local.hosted_zone
}

# LINK SHARED RESOLVER RULE WITH VPC

data "aws_route53_resolver_rule" "example_local" {
  domain_name = "example.local"
  rule_type   = "FORWARD"
}

resource "aws_route53_resolver_rule_association" "resolver_rule_vpc_assocation_in_spoke_account_a" {
  resolver_rule_id = data.aws_route53_resolver_rule.example_local.id
  vpc_id           = aws_vpc.my_vpc.id
}

# TRANSIT GATEWAY ATTACHMENT

resource "aws_ec2_transit_gateway_vpc_attachment" "example" {
  transit_gateway_id = var.transit_gateway_id
  vpc_id = "${aws_vpc.my_vpc.id}"
  subnet_ids          = ["${aws_subnet.public_subnet.id}"]

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
}

variable "transit_gateway_id" {
  type = string
}
