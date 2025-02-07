module "hub_account" {
  source = "./hub_account"

  account_a_id = var.account_a_id
  account_b_id = var.account_b_id
  account_a_private_hosted_zone_id = module.spoke_account_a.account_a_private_hosted_zone_id
  account_b_private_hosted_zone_id = module.spoke_account_b.account_b_private_hosted_zone_id

  providers = {
    aws = aws.hub_account
  }
}

module "spoke_account_a" {
  source = "./spoke_account_a"

  aws_ram_resource_share_arn = module.hub_account.aws_ram_resource_share_arn
  dns_vpc_id = module.hub_account.dns_vpc_id

  providers = {
    aws = aws.spoke_account_a
  }
}

module "spoke_account_b" {
  source = "./spoke_account_b"

  aws_ram_resource_share_arn = module.hub_account.aws_ram_resource_share_arn
  dns_vpc_id = module.hub_account.dns_vpc_id

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