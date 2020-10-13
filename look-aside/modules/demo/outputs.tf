output "tgw_id" {
  value = aws_ec2_transit_gateway.tgw.id

  # adding dependancy to ensure TGW is fully initialized before using it
  depends_on = [aws_ec2_transit_gateway.tgw]
}

output "tgw_work_rtb_id" {
  value = aws_ec2_transit_gateway_route_table.work_tgw_rtb.id
}

output "tgw_work_attachements" {
  value = aws_ec2_transit_gateway_vpc_attachment.tgw_att
}

output "workload_subnets" {
  value = aws_subnet.private_workload_subnets
}

output "demo_attackers" {
  value = aws_instance.work_host
}

