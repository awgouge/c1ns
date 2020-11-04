
#---------------------------------------------------------------------------------------
# Security groups for the NSVAs
#---------------------------------------------------------------------------------------
resource aws_security_group mgmt {
  count = local.create_nsva ? 1 : 0

  name        = "NSVAmgmt"
  description = "Only allow outbound traffic from the NSVA instances"
  vpc_id      = aws_vpc.nsvpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.nsvpc_tags, {
    Name = "NSVAmgmt"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource aws_security_group data {
  count = local.create_nsva ? 1 : 0

  name        = "NSVAdata"
  description = "Allow all inbound traffic from the Internet"
  vpc_id      = aws_vpc.nsvpc.id

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

  tags = merge(var.nsvpc_tags, {
    Name = "NSVAdata"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

#---------------------------------------------------------------------------------------
# NSVA Cloudwatch Log Group 
#---------------------------------------------------------------------------------------
resource aws_cloudwatch_log_group nsva {
  count = local.create_nsva ? 1 : 0

  name              = "nsva"
  retention_in_days = 14
  tags              = var.nsvpc_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

resource aws_iam_policy cloudwatch_logs_policy {
  name        = "network-security-cloudwatch_logs_policy"
  policy = <<-EOF
  {  
    "Version": "2012-10-17",  
    "Statement":[  
        {  
            "Action": [  
                "logs:CreateLogGroup",  
                "logs:CreateLogStream",  
                "logs:PutLogEvents"  
            ],  
        "Resource": "arn:aws:logs:*:*:*",  
        "Effect": "Allow"  
        },  
        {  
            "Action": "cloudwatch:PutMetricData",  
            "Resource": "*",  
            "Effect": "Allow"  
        }  
    ]  
  }
  EOF
}

resource aws_iam_role cloudwatch_logs_role {
  depends_on = [aws_iam_policy.cloudwatch_logs_policy]
  name = "network-security-cloudwatch_logs_role"

  assume_role_policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  }
  EOF
}

resource aws_iam_policy_attachment attach_policy {
  depends_on = [aws_iam_policy.cloudwatch_logs_policy,aws_iam_role.cloudwatch_logs_role]
  roles      = [aws_iam_role.cloudwatch_logs_role.name]
  policy_arn = aws_iam_policy.cloudwatch_logs_policy.arn
  name       = "netsec-nsva-iam-policy-attachment"
}

resource aws_iam_instance_profile cns_profile {
  depends_on = [aws_iam_policy.cloudwatch_logs_policy,aws_iam_role.cloudwatch_logs_role]
  name = "network-security-nsva_profile"
  role = aws_iam_role.cloudwatch_logs_role.name
}


#---------------------------------------------------------------------------------------
# NSVAs
#---------------------------------------------------------------------------------------
data aws_ami nsva_ami {
  most_recent = true
  owners      = [local.tprnd_account]

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
  filter {
    name = "name"
    values = ["IPS_AMI--${var.nsva_build}"]
  }
}

resource tls_private_key pri_key {
  count = local.create_nsva ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource aws_key_pair keypair {
  count = local.create_nsva ? 1 : 0

  key_name   = "nsva-ec2"
  public_key = tls_private_key.pri_key[0].public_key_openssh
}

resource aws_instance this {
  for_each = local.create_nsva ? local.mgmt_subnets : {}

  ami                    = data.aws_ami.nsva_ami.id
  instance_type          = var.nsva_instance_type
  subnet_id              = aws_subnet.mgmt_subnets[each.key].id
  key_name               = aws_key_pair.keypair[0].key_name
  vpc_security_group_ids = [aws_security_group.mgmt[0].id]
  monitoring             = true
  iam_instance_profile   = aws_iam_instance_profile.cns_profile.name

  root_block_device {
    delete_on_termination = true
  }

  tags = merge(var.nsvpc_tags, {
    Name   = "NSVA-${each.key}",
  })

  lifecycle {
    ignore_changes = [tags, ami]
  }

  user_data = <<-EOT
    # -- START VTPS CLI
    edit
    log
    cloudwatch ips-event enable
    cloudwatch inspection-event enable
    cloudwatch log-group-name nsva
    commit
    exit
    high-availability
    cloudwatch-health period 10
    commit
    exit
    interface mgmt
    host name NetSecNSVA-${each.key}
    commit
    exit
    exit
    save-config -y
    cloudone register ${var.register_api_key}
    # -- END VTPS CLI
    # -- START VTPS CLOUDWATCH
    log-group-name nsva
    # -- END VTPS CLOUDWATCH
  EOT

  #For future use to unregister NSVA instances from CloudOne console
  provisioner "local-exec" {
    when    = destroy
    command = ""
    on_failure = continue
  }

  depends_on = [aws_cloudwatch_log_group.nsva]
}

#---------------------------------------------------------------------------------------
# NSVA Network Interfaces
#---------------------------------------------------------------------------------------
resource aws_network_interface dataport_eni_As {
  for_each = local.create_nsva ? local.private_inspection_subnets : {}

  subnet_id         = aws_subnet.private_inspection_subnets[each.key].id
  security_groups   = [aws_security_group.data[0].id]
  source_dest_check = false

  tags = merge(var.nsvpc_tags, {
    Name = "NSVA-dataport-A-${each.key}"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource aws_network_interface_attachment dataport_eni_A_attachments {
  for_each = local.create_nsva ? local.private_inspection_subnets : {}

  device_index         = 1
  instance_id          = aws_instance.this[each.key].id
  network_interface_id = aws_network_interface.dataport_eni_As[each.key].id
}

resource aws_network_interface dataport_eni_Bs {
  for_each = local.create_nsva ? local.private_sanitized_subnets : {}

  subnet_id         = aws_subnet.private_sanitized_subnets[each.key].id
  security_groups   = [aws_security_group.data[0].id]
  source_dest_check = false

  tags = merge(var.nsvpc_tags, {
    Name = "NSVA-dataport-B-${each.key}"
  })

  lifecycle {
    ignore_changes = [tags]
  }
}

resource aws_network_interface_attachment dataport_eni_B_attachments {
  for_each = local.create_nsva ? local.private_sanitized_subnets : {}

  device_index         = 2
  instance_id          = aws_instance.this[each.key].id
  network_interface_id = aws_network_interface.dataport_eni_Bs[each.key].id

  # depends_on required since eni_A needs to be connected first before eni_B to avoid NSVA dataport swaps
  depends_on = [aws_network_interface_attachment.dataport_eni_A_attachments]
}

#---------------------------------------------------------------------------------------
# Route from the Unbypass Route Table to the NSVA
#---------------------------------------------------------------------------------------
resource aws_route con_to_eni_A {
  for_each = local.create_nsva ? local.private_connection_subnets : {}

  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = aws_route_table.connection_unbypass_route_table[each.key].id
  network_interface_id   = aws_network_interface.dataport_eni_As[each.key].id
}

#---------------------------------------------------------------------------------------
# Route from the Failover Route Table to the NSVA in the other AZ
#---------------------------------------------------------------------------------------
resource aws_route fail_to_eni_A_az0 {
  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = aws_route_table.connection_failover_route_table["${var.nsvpc_azs[0]}"].id
  network_interface_id   = aws_network_interface.dataport_eni_As["${var.nsvpc_azs[1]}"].id
}

resource aws_route fail_to_eni_A_az1 {
  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = aws_route_table.connection_failover_route_table["${var.nsvpc_azs[1]}"].id
  network_interface_id   = aws_network_interface.dataport_eni_As["${var.nsvpc_azs[0]}"].id
}
