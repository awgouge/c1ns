
locals {
  create_nsva      = var.register_api_key != ""
  tprnd_account    = "511311637224"

  private_inspection_subnets = {
    "${var.nsvpc_azs[0]}" = cidrsubnet(var.nsvpc_cidr, 4, 0)
    "${var.nsvpc_azs[1]}" = cidrsubnet(var.nsvpc_cidr, 4, 1)
  }

  private_sanitized_subnets = {
    "${var.nsvpc_azs[0]}" = cidrsubnet(var.nsvpc_cidr, 4, 2)
    "${var.nsvpc_azs[1]}" = cidrsubnet(var.nsvpc_cidr, 4, 3)
  }

  private_connection_subnets = {
    "${var.nsvpc_azs[0]}" = cidrsubnet(var.nsvpc_cidr, 4, 4)
    "${var.nsvpc_azs[1]}" = cidrsubnet(var.nsvpc_cidr, 4, 5)
  }

  public_subnets = {
    "${var.nsvpc_azs[0]}" = cidrsubnet(var.nsvpc_cidr, 4, 6)
    "${var.nsvpc_azs[1]}" = cidrsubnet(var.nsvpc_cidr, 4, 7)
  }

  mgmt_subnets = {
    "${var.nsvpc_azs[0]}" = cidrsubnet(var.nsvpc_cidr, 4, 8)
    "${var.nsvpc_azs[1]}" = cidrsubnet(var.nsvpc_cidr, 4, 9)
  }
}

data "aws_ec2_transit_gateway" "tgw" {
  id = var.tgw_id
}

resource "aws_vpc" "nsvpc" {
  cidr_block = var.nsvpc_cidr

  tags = merge(var.nsvpc_tags, {
    Name = var.nsvpc_name
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_subnet" "mgmt_subnets" {
  for_each = local.mgmt_subnets

  availability_zone = each.key
  cidr_block        = each.value
  vpc_id            = aws_vpc.nsvpc.id 

  tags = merge(var.nsvpc_tags, {
    Name="network-security-mgmt-subnet-${each.key}"
    netsec_subnet_type="management"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_subnet" "public_subnets" {
  for_each = local.public_subnets

  availability_zone = each.key
  cidr_block        = each.value
  vpc_id            = aws_vpc.nsvpc.id 

  tags = merge(var.nsvpc_tags, {
    Name="network-security-public-subnet-${each.key}"
    netsec_subnet_type="public"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_subnet" "private_connection_subnets" {
  for_each = local.private_connection_subnets

  availability_zone = each.key
  cidr_block        = each.value
  vpc_id            = aws_vpc.nsvpc.id 

  tags = merge(var.nsvpc_tags, {
    Name="network-security-private_connection_subnet-${each.key}"
    netsec_subnet_type="connection"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_subnet" "private_sanitized_subnets" {
  for_each = local.private_sanitized_subnets

  availability_zone = each.key
  cidr_block        = each.value
  vpc_id            = aws_vpc.nsvpc.id 

  tags = merge(var.nsvpc_tags, {
    Name="network-security-private_sanitized_subnet-${each.key}"
    netsec_subnet_type="sanitized"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_subnet" "private_inspection_subnets" {
  for_each = local.private_inspection_subnets

  availability_zone = each.key
  cidr_block        = each.value
  vpc_id            = aws_vpc.nsvpc.id 

  tags = merge(var.nsvpc_tags, {
    Name="network-security-private_inspection_subnet-${each.key}"
    netsec_subnet_type="inspection"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.nsvpc.id

  tags = merge(var.nsvpc_tags, {
    Name="network-security-IGW"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_eip" "ngw_eips" {
  for_each = local.public_subnets

  vpc = true

  tags = merge(var.nsvpc_tags, {
    Name="network-security-NGW-EIP-${each.key}"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_nat_gateway" "ngws" {
  for_each = local.public_subnets

  allocation_id = aws_eip.ngw_eips[each.key].id
  subnet_id     = aws_subnet.public_subnets[each.key].id
  depends_on    = [aws_internet_gateway.igw]

  tags = merge(var.nsvpc_tags, {
    Name="network-security-NGW-${each.key}"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

#One management route table per subnet
resource "aws_route_table" "mgmt_rtbs" {
  for_each = local.mgmt_subnets

  vpc_id = aws_vpc.nsvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngws[each.key].id
  }

  tags = merge(var.nsvpc_tags, {
    Name="network-security-mgmt-rtb-${each.key}"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_route_table_association" "mgmt_rtb_ass" {
  for_each = local.mgmt_subnets

  subnet_id      = aws_subnet.mgmt_subnets[each.key].id
  route_table_id = aws_route_table.mgmt_rtbs[each.key].id
}

# Create public route table for each public subnet
resource "aws_route_table" "public_rtb" {
  for_each = local.public_subnets

  vpc_id = aws_vpc.nsvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  route {
    cidr_block = "192.168.0.0/16"
    network_interface_id = aws_network_interface.dataport_eni_As[each.key].id
  }

  route {
    cidr_block = "172.16.0.0/12"
    network_interface_id = aws_network_interface.dataport_eni_As[each.key].id
  }

  route {
    cidr_block = "10.0.0.0/8"
    network_interface_id = aws_network_interface.dataport_eni_As[each.key].id
  }

  tags = merge(var.nsvpc_tags, {
    Name="network-security-public-rtb-${each.key}"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_route_table_association" "public_rtb_ass" {
  for_each = local.public_subnets

  subnet_id      = aws_subnet.public_subnets[each.key].id
  route_table_id = aws_route_table.public_rtb[each.key].id
}

#One sanitized subnet route table per subnet
resource "aws_route_table" "private_sanitized_subnets_rtbs" {
  for_each = local.private_sanitized_subnets

  vpc_id = aws_vpc.nsvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngws[each.key].id
  }

  route {
    cidr_block = "192.168.0.0/16"
    transit_gateway_id = data.aws_ec2_transit_gateway.tgw.id
  }

  route {
    cidr_block = "172.16.0.0/12"
    transit_gateway_id = data.aws_ec2_transit_gateway.tgw.id
  }

  route {
    cidr_block = "10.0.0.0/8"
    transit_gateway_id = data.aws_ec2_transit_gateway.tgw.id
  }

  tags = merge(var.nsvpc_tags, {
    Name="network-security-sanitized-rtb-${each.key}"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_route_table_association" "private_sanitized_subnets_rtb_ass" {
  for_each = local.private_sanitized_subnets

  subnet_id      = aws_subnet.private_sanitized_subnets[each.key].id
  route_table_id = aws_route_table.private_sanitized_subnets_rtbs[each.key].id
}

#create TGW attachments
data "aws_subnet_ids" "conn_sub_ids" {
  vpc_id = aws_vpc.nsvpc.id

  tags = {
    netsec_subnet_type = "connection"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "tgw_att" {
  subnet_ids                                      = data.aws_subnet_ids.conn_sub_ids.ids
  transit_gateway_id                              = data.aws_ec2_transit_gateway.tgw.id
  vpc_id                                          = aws_vpc.nsvpc.id
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.nsvpc_tags, {
    Name="network-security-tgw-att"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_ec2_transit_gateway_route_table" "netsec_tgw_rtb" {
  transit_gateway_id = data.aws_ec2_transit_gateway.tgw.id

  tags = merge(var.nsvpc_tags, {
    Name="tgw-netsec-rtb"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "tgw_ass" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.tgw_att.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.netsec_tgw_rtb.id
}

#Unique route table for each connection subnet
resource "aws_route_table" "connection_bypass_route_table" {
  for_each = local.private_connection_subnets

  vpc_id = aws_vpc.nsvpc.id
  
  route {
    cidr_block = "0.0.0.0/0"
    transit_gateway_id = data.aws_ec2_transit_gateway.tgw.id
  }

  tags = merge(var.nsvpc_tags, {
    Name="inspection-bypass-connection-route-table-${each.key}"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_route_table" "connection_unbypass_route_table" {
  for_each = local.private_connection_subnets

  vpc_id = aws_vpc.nsvpc.id

  tags = merge(var.nsvpc_tags, {
    Name="inspection-unbypass-connection-route-table-${each.key}"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_route_table" "connection_failover_route_table" {
  for_each = local.private_connection_subnets

  vpc_id = aws_vpc.nsvpc.id

  tags = merge(var.nsvpc_tags, {
    Name="inspection-failover-connection-route-table-${each.key}"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_route_table_association" "conn_rtb_ass" {
  for_each = local.private_connection_subnets

  subnet_id      = aws_subnet.private_connection_subnets[each.key].id
  route_table_id = aws_route_table.connection_unbypass_route_table[each.key].id
}