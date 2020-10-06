provider aws {
  profile = "default"
  version = "~> 3.0"
  region  = var.region
}

data aws_availability_zones available {
  state = "available"
}

locals {
  common_tags = {
    Environment = var.stage
    Date        = timestamp()
    CreatedBy   = var.user
  }
}

module "demo" {
  source            = "../../modules/demo"
  demo_cidrs         = ["10.10.1.0/24", "10.10.2.0/24"]
  demo_tags         = local.common_tags
  demo_azs          = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "nsvpc" {
  depends_on        = [module.demo]
  tgw_id            = module.demo.tgw_id
  source            = "../../modules/nsvpc"
  nsvpc_cidr        = "192.168.200.0/24"
  nsvpc_name        = "Network Security VPC"
  nsvpc_tags        = local.common_tags
  nsvpc_azs         = slice(data.aws_availability_zones.available.names, 0, 2)
  register_api_key  = var.api_key #Cloud One API key used to register the instances
}

