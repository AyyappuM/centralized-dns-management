provider "aws" {
  alias   = "hub_account"
  profile = "a1"
}

provider "aws" {
  alias   = "spoke_account_a"
  profile = "a2"
}

provider "aws" {
  alias   = "spoke_account_b"
  profile = "a3"
}

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}
