module "hub_account" {
  source = "./hub_account"

  providers = {
    aws = aws.hub_account
  }
}

module "spoke_account_a" {
  source = "./spoke_account_a"

  providers = {
    aws = aws.spoke_account_a
  }

  depends_on = [
    module.hub_account
  ]
}

module "spoke_account_b" {
  source = "./spoke_account_b"

  providers = {
    aws = aws.spoke_account_b
  }

  depends_on = [
    module.hub_account
  ]
}