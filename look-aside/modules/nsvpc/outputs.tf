output "nsvpc_id" {
  value = aws_vpc.nsvpc.id
}

output "netsec-tgw-rtb-id" {
  value = aws_ec2_transit_gateway_route_table.netsec_tgw_rtb.id
}

output "netsec-tgw-attachment-id" {
  value = aws_ec2_transit_gateway_vpc_attachment.tgw_att.id
}