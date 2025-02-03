data "aws_availability_zones" "available" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

variable "spoke_account_a_id" {
  type        = string
}

variable "spoke_account_b_id" {
  type        = string
}

variable "account_a_private_hosted_zone_id" {
  type        = string
}

variable "account_b_private_hosted_zone_id" {
  type        = string
}

# DEPLOY DNS VPC

resource "aws_vpc" "dns_vpc" {
  cidr_block = "192.168.0.0/24"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "dns-vpc"
  }
}

output "dns_vpc_id" {
  value = aws_vpc.dns_vpc.id
}

# DEPLOY SECURITY GROUP

resource "aws_security_group" "allow_all_traffic" {
  name        = "allow-all-traffic"
  description = "Security group to allow all inbound and outbound traffic"
  vpc_id      = aws_vpc.dns_vpc.id  # Attach this to the VPC created earlier

  # Allow DNS traffic (port 53) for Route 53 Resolver endpoints
  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
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

# CREATE SUBNETS IN TWO AZ

resource "aws_subnet" "private_subnet_1" {
  vpc_id     = aws_vpc.dns_vpc.id
  cidr_block = "192.168.0.0/25"
  availability_zone = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "private-subnet-1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id     = aws_vpc.dns_vpc.id
  cidr_block = "192.168.0.128/25"
  availability_zone = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "private-subnet-2"
  }
}

# ROUTE53 RESOLVER RULE

resource "aws_route53_resolver_rule" "example" {
  domain_name = "example.local"
  name        = "example-local-forward-rule"
  rule_type   = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound.id

  dynamic "target_ip" {
    for_each = aws_route53_resolver_endpoint.inbound.ip_address
    content {
      ip = target_ip.value.ip
      port = 53
    }
  } 
}

# ASSOCIATE RESOLVER RULE WITH VPC

resource "aws_route53_resolver_rule_association" "example" {
  resolver_rule_id = aws_route53_resolver_rule.example.id
  vpc_id           = aws_vpc.dns_vpc.id
}

# ROUTE 53 OUTBOUND ENDPOINT

resource "aws_route53_resolver_endpoint" "outbound" {
  name      = "outbound-endpoint"
  direction = "OUTBOUND"

  security_group_ids = [aws_security_group.allow_all_traffic.id]

  ip_address {
    subnet_id = aws_subnet.private_subnet_1.id
  }

  ip_address {
    subnet_id = aws_subnet.private_subnet_2.id
  }
}

# ROUTE 53 INBOUND ENDPOINT

resource "aws_route53_resolver_endpoint" "inbound" {
  name      = "inbound-endpoint"
  direction = "INBOUND"

  security_group_ids = [aws_security_group.allow_all_traffic.id]

  ip_address {
    subnet_id = aws_subnet.private_subnet_1.id
  }

  ip_address {
    subnet_id = aws_subnet.private_subnet_2.id
  }
}

output "resolver_endpoint_ips" {
  value = [for ip in aws_route53_resolver_endpoint.inbound.ip_address : ip.ip]
}

# RAM RESOURCE SHARE

resource "aws_ram_resource_share" "example" {
  name     = "example-share"
  allow_external_principals = true
}

resource "aws_ram_principal_association" "account_a" {
  principal = var.spoke_account_a_id
  resource_share_arn = aws_ram_resource_share.example.arn
}

resource "aws_ram_principal_association" "account_b" {
  principal = var.spoke_account_b_id
  resource_share_arn = aws_ram_resource_share.example.arn
}

resource "aws_ram_resource_association" "resolver_rule" {
  resource_arn = aws_route53_resolver_rule.example.arn
  resource_share_arn = aws_ram_resource_share.example.arn
}

output "aws_ram_resource_share_arn" {
  value = aws_ram_resource_share.example.arn
}

# HOSTED ZONE & VPC ASSOCIATION

resource "aws_route53_zone_association" "private_hz_in_spoke_account_a_dns_vpc_in_hub_account_association" {
  zone_id = var.account_a_private_hosted_zone_id
  vpc_id  = aws_vpc.dns_vpc.id
}

resource "aws_route53_zone_association" "private_hz_in_spoke_account_b_dns_vpc_in_hub_account_association" {
  zone_id = var.account_b_private_hosted_zone_id
  vpc_id  = aws_vpc.dns_vpc.id
}

# TRANSIT GATEWAY

resource "aws_ec2_transit_gateway" "example" {
  description = "example"
  auto_accept_shared_attachments = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"

  tags = {
    Name        = "Shared-TGW"
  }
}

resource "aws_ram_resource_association" "share_tgw" {
  resource_arn       = aws_ec2_transit_gateway.example.arn
  resource_share_arn = aws_ram_resource_share.example.arn
}

output "transit_gateway_id" {
  value = aws_ec2_transit_gateway.example.id
}

