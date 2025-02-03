data "aws_availability_zones" "available" {}
data "aws_region" "current" {}

# DEPLOY DNS VPC

resource "aws_vpc" "dns_vpc" {
  cidr_block = "192.168.0.0/24"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "dns-vpc"
  }
}

# DEPLOY SECURITY GROUP

resource "aws_security_group" "allow_all_traffic" {
  name        = "allow-all-traffic"
  description = "Security group to allow all inbound and outbound traffic"
  vpc_id      = aws_vpc.dns_vpc.id  # Attach this to the VPC created earlier

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

