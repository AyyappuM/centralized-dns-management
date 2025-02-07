module "hub_account" {
  source = "./hub_account"

  spoke_account_a_id = module.spoke_account_a.account_id
  spoke_account_b_id = module.spoke_account_b.account_id
  account_a_private_hosted_zone_id = module.spoke_account_a.account_a_private_hosted_zone_id
  account_b_private_hosted_zone_id = module.spoke_account_b.account_b_private_hosted_zone_id

  providers = {
    aws = aws.hub_account
  }
}

module "spoke_account_a" {
  source = "./spoke_account_a"

  hub_account_id = module.hub_account.account_id
  spoke_account_b_id = module.spoke_account_b.account_id
  aws_ram_resource_share_arn = module.hub_account.aws_ram_resource_share_arn
  dns_vpc_id = module.hub_account.dns_vpc_id
  transit_gateway_id = module.hub_account.transit_gateway_id  

  providers = {
    aws = aws.spoke_account_a
  }
}

module "spoke_account_b" {
  source = "./spoke_account_b"

  hub_account_id = module.hub_account.account_id
  spoke_account_a_id = module.spoke_account_a.account_id
  aws_ram_resource_share_arn = module.hub_account.aws_ram_resource_share_arn
  dns_vpc_id = module.hub_account.dns_vpc_id
  transit_gateway_id = module.hub_account.transit_gateway_id  

  providers = {
    aws = aws.spoke_account_b
  }
}

output "account_a_private_hosted_zone_id" {
  value = module.spoke_account_a.account_a_private_hosted_zone_id
}

output "account_b_private_hosted_zone_id" {
  value = module.spoke_account_b.account_b_private_hosted_zone_id
}

output "resolver_endpoint_ips" {
  value = module.hub_account.resolver_endpoint_ips
}
