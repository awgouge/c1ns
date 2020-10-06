
locals {

  private_workload_subnets = {
    "network-security-test-vpc1" = cidrsubnet(var.demo_cidrs[0], 4, 0)
    "network-security-test-vpc2" = cidrsubnet(var.demo_cidrs[1], 4, 0)
  }
  private_connection_subnets = {
    "network-security-test-vpc1" = cidrsubnet(var.demo_cidrs[0], 4, 1)
    "network-security-test-vpc2" = cidrsubnet(var.demo_cidrs[1], 4, 1)
  }
}

resource "aws_vpc" "vpcs" {
  for_each = local.private_connection_subnets

  cidr_block = var.demo_cidrs[index(keys(local.private_connection_subnets), each.key)]

  tags = merge(var.demo_tags, {
    Name = each.key
  })
}

resource "aws_internet_gateway" "igw" {
  for_each = local.private_connection_subnets

  vpc_id   = aws_vpc.vpcs[each.key].id 

  tags = merge(var.demo_tags, {
    Name = "${each.key}-igw"
  })
}

resource "aws_subnet" "private_connection_subnets" {
  for_each = local.private_connection_subnets

  availability_zone = var.demo_azs[0]
  cidr_block        = each.value
  vpc_id            = aws_vpc.vpcs[each.key].id 

  tags = merge(var.demo_tags, {
    Name = "${each.key}-private-conn-sub"
  })
}

resource "aws_subnet" "private_workload_subnets" {
  for_each = local.private_workload_subnets

  availability_zone = var.demo_azs[0]
  cidr_block        = each.value
  vpc_id            = aws_vpc.vpcs[each.key].id 

  tags = merge(var.demo_tags, {
    Name = "${each.key}-private-work-sub"
  })
}

resource "aws_route_table" "work_rtbs" {
  for_each = local.private_workload_subnets

  vpc_id = aws_vpc.vpcs[each.key].id 

  route {
    cidr_block             = "0.0.0.0/0"
    gateway_id             = aws_internet_gateway.igw[each.key].id
  }
  route {
    cidr_block             = "192.168.0.0/16"
    transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
  }
  route {
    cidr_block             = "172.16.0.0/12"
    transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
  }
  route {
    cidr_block             = "10.0.0.0/8"
    transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
  }

  tags = merge(var.demo_tags, {
    Name="${each.key}-private-work-rtb"
  })
}

resource "aws_route_table_association" "work_rtb_ass" {
  for_each = local.private_workload_subnets

  subnet_id      = aws_subnet.private_workload_subnets[each.key].id
  route_table_id = aws_route_table.work_rtbs[each.key].id
}

resource "aws_route_table" "conn_rtbs" {
  for_each = local.private_connection_subnets

  vpc_id = aws_vpc.vpcs[each.key].id 

  tags = merge(var.demo_tags, {
    Name="${each.key}-private-conn-rtb"
  })
}

resource "aws_ec2_transit_gateway" "tgw" {
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"

  tags = merge(var.demo_tags, {
    Name="network-security-test-tgw"
  })
}

resource "aws_ec2_transit_gateway_route_table" "work_tgw_rtb" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id

  tags = merge(var.demo_tags, {
    Name="network-security-test-tgw-work-rtb"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "tgw_att" {
  for_each = local.private_connection_subnets

  subnet_ids                                      = [aws_subnet.private_connection_subnets[each.key].id]
  transit_gateway_id                              = aws_ec2_transit_gateway.tgw.id
  vpc_id                                          = aws_vpc.vpcs[each.key].id
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.demo_tags, {
    Name="${each.key}-tgw-att"
  })
}

resource "aws_ec2_transit_gateway_route_table_association" "tgw_ass" {
  for_each = local.private_connection_subnets

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.tgw_att[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.work_tgw_rtb.id
}

resource "aws_ec2_transit_gateway_route" "work_tgw_rtb_route" {
  for_each = local.private_workload_subnets

  destination_cidr_block         = each.value
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.tgw_att[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.work_tgw_rtb.id
}

#create security group for the test workloads
resource "aws_security_group" "sgs" {
  for_each = local.private_workload_subnets

  vpc_id      = aws_vpc.vpcs[each.key].id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.demo_tags, {
    Name="${each.key}-demo-workload-SG"
  })
}

#Add the actual workloads to use for testing
data "aws_ami" "ubuntu_server_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource tls_private_key pri_key {
  algorithm = "RSA"
  rsa_bits  = 4096
}
#FIXME: Change to store pem natively in AWS
resource "local_file" "private_key" {
  content = tls_private_key.pri_key.private_key_pem
  filename = "demokey.pem"
}

resource aws_key_pair keypair {
  key_name   = "netsec-test-workload-ec2"
  public_key = tls_private_key.pri_key.public_key_openssh
}

resource "aws_instance" "work_host" {
  for_each = local.private_workload_subnets

  ami                         = data.aws_ami.ubuntu_server_ami.id
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.keypair.key_name
  vpc_security_group_ids      = [aws_security_group.sgs[each.key].id]
  subnet_id                   = aws_subnet.private_workload_subnets[each.key].id
  associate_public_ip_address = true

  user_data = <<EOF
  #cloud-config
  repo_update: true
  repo_upgrade: all

  packages:
   - screen

  runcmd:
    - screen -S testping2 -dm ping ${cidrhost(local.private_workload_subnets["network-security-test-vpc2"], 15)}
    - screen -S testping1 -dm ping ${cidrhost(local.private_workload_subnets["network-security-test-vpc1"], 15)}
  EOF

  tags = merge(var.demo_tags, {
    Name="${each.key}-test-workload"
  })
}