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
  demo_cidrs        = ["10.10.1.0/24", "10.10.2.0/24"]
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

resource "aws_ec2_transit_gateway_route" "demo_tgw_rtb_route" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = module.nsvpc.netsec_tgw_attachment_id
  transit_gateway_route_table_id = module.demo.tgw_work_rtb_id
}


resource "aws_ec2_transit_gateway_route" "netsec_tgw_rtb_route" {
  for_each = module.demo.workload_subnets

  destination_cidr_block         = module.demo.workload_subnets[each.key].cidr_block
  transit_gateway_attachment_id  = module.demo.tgw_work_attachements[each.key].id
  transit_gateway_route_table_id = module.nsvpc.netsec_tgw_rtb_id
}

output "test_websites" {
  value = [
    for vpc_name, ip in zipmap(
      sort(keys(module.demo.demo_attackers)),
      sort(values(module.demo.demo_attackers)[*].public_ip)) :
      map("name", vpc_name, "IP", format("http://%s:5000", ip))
  ]
}
