output "nsvpc_id" {
  value = aws_vpc.nsvpc.id
}

output "netsec_tgw_rtb_id" {
  value = aws_ec2_transit_gateway_route_table.netsec_tgw_rtb.id
}

output "netsec_tgw_attachment_id" {
  value = aws_ec2_transit_gateway_vpc_attachment.tgw_att.id
}