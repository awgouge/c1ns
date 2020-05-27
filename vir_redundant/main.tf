#Set the region and use AWS
provider "aws" {
  profile = "default"
  version = "~> 2.8"
  region  = var.region
}

#Get AZs in the region
data "aws_availability_zones" "azs" {
    state = "available"
}

####Attacker VPC####
#Create the VPC and Security Group
resource "aws_vpc" "attacker_vpc" {
  cidr_block = var.attacker_vpc.cidr

  tags = {
    Name        = format("%s - %s", var.unique_id, var.attacker_vpc.name)
    Description = format("%s - %s", var.unique_id, var.attacker_vpc.desc)
  }
}
resource "aws_security_group" "attacker_sg" {
  vpc_id      = aws_vpc.attacker_vpc.id
  name        = format("%s - %s - %s", var.unique_id, var.attacker_vpc.name, "Attacker - SG")
  description = format("%s - %s - %s", var.unique_id, var.attacker_vpc.name, "SG")

  #allow SSH connections from any IP.
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = list(var.my_pub_ip)
  }

  #allow connect to the attack website.
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = [var.my_pub_ip]
  }

  #allow any traffic to egress to the Internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#Add and IGW
resource "aws_internet_gateway" "attacker_igw" {
  vpc_id     = aws_vpc.attacker_vpc.id
  tags = {
    Name = format("%s - %s - %s", var.unique_id, var.attacker_vpc.name, "IGW")
  }
}

#Create public subnet for the Attacker VPC
resource "aws_subnet" "attacker_sub1" {
  vpc_id                  = aws_vpc.attacker_vpc.id
  cidr_block              = var.attacker_vpc.pub_sub1_cidr
  map_public_ip_on_launch = "true"

  tags = {
    Name = format("%s - %s", var.unique_id, var.attacker_vpc.pub_sub1_name)
  }
}
resource "aws_route_table" "attacker_sub1_rtb" {
  vpc_id = aws_vpc.attacker_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    gateway_id     = aws_internet_gateway.attacker_igw.id
  }
  tags = {
    Name = format("%s - %s - %s", var.unique_id, var.attacker_vpc.pub_sub1_name, "RTB")
  }
}
resource "aws_route_table_association" "attacker_sub1_rtb_ass" {
  subnet_id      = aws_subnet.attacker_sub1.id
  route_table_id = aws_route_table.attacker_sub1_rtb.id
}
resource "aws_route" "attacker_sub1_default_route" {
  route_table_id            = aws_route_table.attacker_sub1_rtb.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id                = aws_internet_gateway.attacker_igw.id
}

####Internet facing VPC####
#Create the Internet facing VPC
resource "aws_vpc" "inet_vpc" {
  cidr_block = var.inet_vpc.cidr

  tags = {
    Name        = format("%s - %s", var.unique_id, var.inet_vpc.name)
    Description = format("%s - %s", var.unique_id, var.inet_vpc.desc)
  }
}
resource "aws_security_group" "inet_pub_sg" {
  vpc_id      = aws_vpc.inet_vpc.id
  name        = format("%s - %s - %s", var.unique_id, var.inet_vpc.name, "Public Subnet - SG")
  description = format("%s - %s - %s", var.unique_id, var.inet_vpc.name, "SG")

  #allow SSH connections from any IP.
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #allow any traffic to egress to the Internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "inet_ips_sg" {
  vpc_id      = aws_vpc.inet_vpc.id
  name        = format("%s - %s - %s", var.unique_id, var.inet_vpc.name, "IPS - SG")
  description = format("%s - %s - %s", var.unique_id, var.inet_vpc.name, "IPS - SG")

  #allow all traffic from anywhere
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #allow any traffic to egress to the Internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "inet_prot_sg" {
  vpc_id      = aws_vpc.inet_vpc.id
  name        = format("%s - %s - %s", var.unique_id, var.inet_vpc.name, "Protected Subnet - SG")
  description = format("%s - %s - %s", var.unique_id, var.inet_vpc.name, "SG")

  #allow SSH connections from any IP.
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = list(var.my_pub_ip, join("/", [aws_eip.attacker_eip.public_ip, "32"]))
  }
  ingress {
    from_port   = var.struts_port
    to_port     = var.struts_port
    protocol    = "tcp"
    cidr_blocks = list(var.my_pub_ip, join("/", [aws_eip.attacker_eip.public_ip, "32"]))
  }
  ingress {
    from_port   = var.dvwa_port
    to_port     = var.dvwa_port
    protocol    = "tcp"
    cidr_blocks = list(var.my_pub_ip, join("/", [aws_eip.attacker_eip.public_ip, "32"]))
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = list(var.my_pub_ip, join("/", [aws_eip.attacker_eip.public_ip, "32"]))
  }
  #allow any traffic to egress to the Internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "inet_mgmt_sg" {
  vpc_id      = aws_vpc.inet_vpc.id
  name        = format("%s - %s - %s", var.unique_id, var.inet_vpc.name, "Management Subnet - SG")
  description = format("%s - %s - %s", var.unique_id, var.inet_vpc.name, "SG")

  #allow SSH connections from any IP.
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  #allow any traffic to egress to the Internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#Add an IGW
resource "aws_internet_gateway" "igw" {
  vpc_id     = aws_vpc.inet_vpc.id
  tags = {
    Name = format("%s - %s - %s", var.unique_id, var.inet_vpc.name, "IGW")
  }
}
#VIR Route Table
resource "aws_route_table" "igw_pri_rtb" {
  vpc_id = aws_vpc.inet_vpc.id

  route {
    cidr_block = var.inet_vpc.prot_sub1_cidr
    network_interface_id = aws_network_interface.cnp1_1b.id
  }

  tags = {
    Name = format("%s - %s", var.unique_id, "IGW Primary RTB")
  }
}
resource "aws_route_table" "igw_sec_rtb" {
  vpc_id = aws_vpc.inet_vpc.id

  route {
    cidr_block = var.inet_vpc.prot_sub1_cidr
    network_interface_id = aws_network_interface.cnp2_1b.id
  }

  tags = {
    Name = format("%s - %s", var.unique_id, "IGW Secondary RTB")
  }
}
#Create Public Subnets for Internet VPC
resource "aws_subnet" "inet_pub_sub1" {
  vpc_id                  = aws_vpc.inet_vpc.id
  cidr_block              = var.inet_vpc.pub_sub1_cidr
  map_public_ip_on_launch = "true"
  availability_zone = data.aws_availability_zones.azs.names[0]
  tags = {
    Name = format("%s - %s", var.unique_id, var.inet_vpc.pub_sub1_name)
  }
}
resource "aws_route_table" "pub_sub1_rtb" {
  vpc_id = aws_vpc.inet_vpc.id

  tags = {
    Name = format("%s - %s - %s", var.unique_id, var.inet_vpc.pub_sub1_name, "RTB")
  }
}
resource "aws_route_table_association" "pub_sub1_rtb_ass" {
  subnet_id      = aws_subnet.inet_pub_sub1.id
  route_table_id = aws_route_table.pub_sub1_rtb.id
}
resource "aws_route" "inet_pub_sub1_default_route" {
  route_table_id            = aws_route_table.pub_sub1_rtb.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id                = aws_internet_gateway.igw.id
}
resource "aws_subnet" "inet_pub_sub2" {
  vpc_id                  = aws_vpc.inet_vpc.id
  cidr_block              = var.inet_vpc.pub_sub2_cidr
  map_public_ip_on_launch = "true"
  availability_zone = data.aws_availability_zones.azs.names[1]
  tags = {
    Name = format("%s - %s", var.unique_id, var.inet_vpc.pub_sub2_name)
  }
}
resource "aws_route_table" "pub_sub2_rtb" {
  vpc_id = aws_vpc.inet_vpc.id

  tags = {
    Name = format("%s - %s - %s", var.unique_id, var.inet_vpc.pub_sub2_name, "RTB")
  }
}
resource "aws_route_table_association" "pub_sub2_rtb_ass" {
  subnet_id      = aws_subnet.inet_pub_sub2.id
  route_table_id = aws_route_table.pub_sub2_rtb.id
}
resource "aws_route" "inet_pub_sub2_default_route" {
  route_table_id            = aws_route_table.pub_sub2_rtb.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id                = aws_internet_gateway.igw.id
}

#Create an NGW in each AZ
resource "aws_eip" "ngw1_eip" {
  vpc = true
}
resource "aws_nat_gateway" "ngw1" {
  allocation_id = aws_eip.ngw1_eip.id
  subnet_id     = aws_subnet.inet_pub_sub1.id
  tags = {
    Name = format("%s - %s", var.unique_id, "NGW1")
  }
}
/*
resource "aws_nat_gateway" "ngw2" {
  allocation_id = aws_eip.ngw2_eip.id
  subnet_id     = aws_subnet.inet_prot_sub2.id
  tags = {
    Name = format("%s - %s", var.unique_id, "NGW2")
  }
}
resource "aws_eip" "ngw2_eip" {
  vpc = true
}
*/

#Create Management Subnets for Internet VPC
resource "aws_subnet" "inet_mgmt_sub1" {
  vpc_id            = aws_vpc.inet_vpc.id
  cidr_block        = var.inet_vpc.mgmt_sub1_cidr
  availability_zone = aws_subnet.inet_pub_sub1.availability_zone

  tags = {
    Name = format("%s - %s", var.unique_id, var.inet_vpc.mgmt_sub1_name)
  }
}
resource "aws_route_table" "inet_mgmt_sub1_rtb" {
  vpc_id     = aws_vpc.inet_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw1.id
  }
  tags = {
    Name = format("%s - %s - %s", var.unique_id, var.inet_vpc.mgmt_sub1_name, "RTB")
  }
}
resource "aws_route_table_association" "inet_mgmt_sub1_rtb_ass" {
  subnet_id      = aws_subnet.inet_mgmt_sub1.id
  route_table_id = aws_route_table.inet_mgmt_sub1_rtb.id
}
resource "aws_subnet" "inet_mgmt_sub2" {
  vpc_id            = aws_vpc.inet_vpc.id
  cidr_block        = var.inet_vpc.mgmt_sub2_cidr
  availability_zone = aws_subnet.inet_pub_sub2.availability_zone

  tags = {
    Name = format("%s - %s", var.unique_id, var.inet_vpc.mgmt_sub2_name)
  }
}
resource "aws_route_table" "inet_mgmt_sub2_rtb" {
  vpc_id     = aws_vpc.inet_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw1.id
  }
  tags = {
    Name = format("%s - %s - %s", var.unique_id, var.inet_vpc.mgmt_sub2_name, "RTB")
  }
}
resource "aws_route_table_association" "inet_mgmt_sub2_rtb_ass" {
  subnet_id      = aws_subnet.inet_mgmt_sub2.id
  route_table_id = aws_route_table.inet_mgmt_sub2_rtb.id
}

#Create Protected Subnets for Internet VPC
resource "aws_subnet" "inet_prot_sub1" {
    vpc_id          = aws_vpc.inet_vpc.id
    cidr_block      = var.inet_vpc.prot_sub1_cidr
    availability_zone = aws_subnet.inet_pub_sub1.availability_zone

    tags = {
        Name = format("%s - %s", var.unique_id, var.inet_vpc.prot_sub1_name)
    }
}
resource "aws_route_table" "inet_prot_sub1_rtb" {
  vpc_id     = aws_vpc.inet_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    gateway_id     = aws_internet_gateway.igw.id
  }
  tags = {
    Name = format("%s - %s - %s", var.unique_id, var.inet_vpc.prot_sub1_name, "RTB")
  }
}
resource "aws_route_table_association" "inet_prot_sub1_rtb_ass" {
  subnet_id      = aws_subnet.inet_prot_sub1.id
  route_table_id = aws_route_table.inet_prot_sub1_rtb.id
}
resource "aws_route_table" "inet_prot_sub1_insp_rtb" {
  vpc_id     = aws_vpc.inet_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    network_interface_id = aws_network_interface.cnp1_1a.id
  }
  tags = {
    Name = format("%s - %s - %s", var.unique_id, var.inet_vpc.prot_sub1_name, "Primary INSPECTING RTB")
  }
}
resource "aws_subnet" "inet_prot_sub2" {
    vpc_id          = aws_vpc.inet_vpc.id
    cidr_block      = var.inet_vpc.prot_sub2_cidr
    availability_zone = aws_subnet.inet_pub_sub2.availability_zone

    tags = {
        Name = format("%s - %s", var.unique_id, var.inet_vpc.prot_sub2_name)
    }
}
resource "aws_route_table" "inet_prot_sub2_rtb" {
  vpc_id     = aws_vpc.inet_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw1.id
  }
  tags = {
    Name = format("%s - %s - %s", var.unique_id, var.inet_vpc.prot_sub2_name, "RTB")
  }
}
resource "aws_route_table_association" "inet_prot_sub2_rtb_ass" {
  subnet_id      = aws_subnet.inet_prot_sub2.id
  route_table_id = aws_route_table.inet_prot_sub2_rtb.id
}
resource "aws_route_table" "inet_prot_sub2_insp_rtb" {
  vpc_id     = aws_vpc.inet_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    network_interface_id = aws_network_interface.cnp2_1a.id
  }
  tags = {
    Name = format("%s - %s - %s", var.unique_id, var.inet_vpc.prot_sub2_name, "Secondary INSPECTING RTB")
  }
}

####instances####
#Ubuntu AMI
data "aws_ami" "ubuntu_ami" {
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
#attacker instance
resource "aws_eip" "attacker_eip" {
  vpc = true
}
resource "aws_eip_association" "attacker_eip_ass" {
  allocation_id = aws_eip.attacker_eip.id
  network_interface_id = aws_network_interface.attacker_eni.id
}
resource "aws_network_interface" "attacker_eni" {
  subnet_id        = aws_subnet.attacker_sub1.id
  security_groups = [aws_security_group.attacker_sg.id]
}
resource "aws_instance" "attacker_host" {
  depends_on             = ["aws_instance.work_host1"]
  ami                    = data.aws_ami.ubuntu_ami.id
  instance_type          = var.types.bastion
  key_name               = var.key_pair
  
  network_interface {
    network_interface_id = aws_network_interface.attacker_eni.id
    device_index         = 0
  }

  provisioner "remote-exec" {
    inline = [<<-EOF
      sudo apt update
      sudo apt install python -y
      sudo apt install python3-venv -y
      sudo apt install python3-pip -y
      git clone https://gitlab.com/howiehowerton/cnp_demo_flask.git
      cd cnp_demo_flask
      pip3 install -r requirements.txt
      export VICTIM_HOST=${aws_eip.work1_eip.public_ip}
      echo ${aws_eip.work1_eip.public_ip} > VICTIM_HOST.txt
      export STRUTS_PORT=${var.struts_port}
      echo ${var.struts_port} > STRUTS_PORT.txt
      #./init.sh
      sudo tee -a /lib/systemd/system/flask_web.service > /dev/null <<EOT
[Unit]
Description=Demo Attack Site
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/cnp_demo_flask
ExecStart=/usr/bin/python3 /home/ubuntu/cnp_demo_flask/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOT
      sudo systemctl daemon-reload
      sudo systemctl enable flask_web.service
      sudo systemctl start flask_web.service
      #python3 app.py &
      EOF
    ]

  connection {
      type = "ssh"
      user = "ubuntu"
      timeout = "3m"
      host = aws_instance.attacker_host.public_ip
      private_key = file(var.private_key_file)
      agent = false
    }
  }
  tags = {
    Name = format("%s - %s", var.unique_id, "Attacker instance")
    Description = "Attacker instance"
  }
}
#C1NS IAM
resource "aws_iam_policy" "cloudwatch_logs_policy" {
  name        = format("%s_%s", var.unique_id, "cloudwatch_logs_policy")
  description = "Policy for loggin health messages to cloudwatch"

  policy = file(var.cloudwatch_logs_policy)
}
resource "aws_iam_role" "cloudwatch_logs_role" {
  depends_on = ["aws_iam_policy.cloudwatch_logs_policy"]
  name = format("%s_%s", var.unique_id, "cloudwatch_logs_role")

  assume_role_policy = file(var.cloudwatch_logs_role)
}
resource "aws_iam_policy_attachment" "attach_policy" {
  depends_on = ["aws_iam_policy.cloudwatch_logs_policy","aws_iam_role.cloudwatch_logs_role"]
  name       = format("%s_%s", var.unique_id, "attach_policy")
  roles      = ["${aws_iam_role.cloudwatch_logs_role.name}"]
  policy_arn = "${aws_iam_policy.cloudwatch_logs_policy.arn}"
}
resource "aws_iam_instance_profile" "cns_profile" {
  depends_on = ["aws_iam_policy.cloudwatch_logs_policy","aws_iam_role.cloudwatch_logs_role"]
  name = format("%s_%s", var.unique_id, "cns_profile")
  role = "${aws_iam_role.cloudwatch_logs_role.name}"
}
#Create CloudWatch LogGroup for instance logging
resource "aws_cloudwatch_log_group" "log_group" {
  depends_on = ["aws_iam_instance_profile.cns_profile","aws_iam_role.cloudwatch_logs_role"]
  name       = var.log_group_name
}
#Bastion Hosts
resource "aws_eip" "bastion1_eip" {
  vpc = true
}
resource "aws_eip_association" "bastion1_eip_ass" {
  allocation_id = aws_eip.bastion1_eip.id
  network_interface_id = aws_network_interface.bastion1_eni.id
}
resource "aws_network_interface" "bastion1_eni" {
  subnet_id        = aws_subnet.inet_pub_sub1.id
  security_groups  = [aws_security_group.inet_pub_sg.id]
}
resource "aws_instance" "bastion_host1" {
  ami                    = data.aws_ami.ubuntu_ami.id
  instance_type          = var.types.bastion
  key_name               = var.key_pair

  network_interface {
    network_interface_id = aws_network_interface.bastion1_eni.id
    device_index         = 0
  }
  provisioner "file" {
    source       = var.private_key_file
    destination  = "~/mykey.pem"
  }

  connection {
    type = "ssh"
    user = "ubuntu"
    timeout = "2m"
    host = aws_eip.bastion1_eip.public_ip
    private_key = file(var.private_key_file)
    agent = false
    }
  
  tags = {
    Name = format("%s - %s", var.unique_id, "Bastion instance 1")
    Description = "Bastion instance 1"
  }
}
#Workload Hosts
resource "aws_eip" "work1_eip" {
  vpc = true
}
resource "aws_eip_association" "work1_eip_ass" {
  allocation_id = aws_eip.work1_eip.id
  network_interface_id = aws_network_interface.work1_eni.id
}
resource "aws_network_interface" "work1_eni" {
  subnet_id        = aws_subnet.inet_prot_sub1.id
  security_groups  = [aws_security_group.inet_prot_sg.id]
}
resource "aws_instance" "work_host1" {
  depends_on = ["aws_instance.cnp1"]
  ami = data.aws_ami.ubuntu_ami.id
  instance_type = var.types.work
  key_name = var.key_pair

  network_interface {
    network_interface_id = aws_network_interface.work1_eni.id
    device_index         = 0
  }

  user_data = <<EOF
  #cloud-config
  repo_update: true
  repo_upgrade: all

  packages:

  runcmd:
    - curl -fsSL https://get.docker.com -o get-docker.sh; sh get-docker.sh
    - [ sh, -c, "sudo docker run -d -p ${var.struts_port}:${var.struts_port} --name lab-apache-struts jrrdev/cve-2017-5638" ]
    - [ sh, -c, "sudo docker run -d -p ${var.dvwa_port}:${var.dvwa_port} --name lab-dvwa vulnerables/web-dvwa" ]
    - systemctl status nginx
 EOF
  tags = {
    Name        = format("%s - %s", var.unique_id, "Workload instance 1")
    Description = "Workload instance 1"
  }
}
/*
resource "aws_instance" "work_host2" {
  depends_on = ["aws_instance.cnp2"]
  ami = data.aws_ami.ubuntu_ami.id
  instance_type = var.types.work
  user_data = <<EOF
  #cloud-config
  repo_update: true
  repo_upgrade: all

  packages:
   - nginx

  runcmd:
    - curl -fsSL https://get.docker.com -o get-docker.sh; sh get-docker.sh
    - [ sh, -c, "sudo docker run -d -p ${var.struts_port}:${var.struts_port} --name lab-apache-struts jrrdev/cve-2017-5638" ]
    - systemctl status nginx
 EOF
  key_name = var.key_pair
  vpc_security_group_ids = [aws_security_group.inet_prot_sg.id]
  subnet_id = aws_subnet.inet_prot_sub2.id
  tags = {
    Name        = format("%s - %s", var.unique_id, "Workload instance 2")
    Description = "Workload instance 2"
  }
}
*/
#Network Security instances
data "aws_ami" "cnp_ami" {
    most_recent = true

    filter {
    name   = "name"
    values = [var.cnp_amis.name]
    }

    filter {
    name   = "virtualization-type"
    values = ["hvm"]
    }

    owners = ["511311637224"] #Dev account
}
#Interfaces for cnp1
resource "aws_network_interface" "cnp1_mgmt" {
    subnet_id       = aws_subnet.inet_mgmt_sub1.id
    security_groups = [aws_security_group.inet_mgmt_sg.id]

    tags = {
    Name        = "CNP1 Mangement Interface"
    Description = "Cloud One Network Security Management Interface"
    }
}
resource "aws_network_interface" "cnp1_1a" {
    subnet_id         = aws_subnet.inet_prot_sub1.id
    security_groups   = [aws_security_group.inet_ips_sg.id]
    source_dest_check = false

    tags = {
    Name        = "CNP1 Interface 1A"
    Description = "Cloud One Network Security Inspection Interface 1A"
    }
}
resource "aws_network_interface" "cnp1_1b" {
    subnet_id         = aws_subnet.inet_pub_sub1.id
    security_groups   = [aws_security_group.inet_ips_sg.id]
    source_dest_check = false

    tags = {
    Name        = "CNP1 Interface 1B"
    Description = "Cloud One Network Security Sanitized Interface 1B"
    }
}
#CNS Instance 1
resource "aws_instance" "cnp1" {
  depends_on = ["aws_iam_instance_profile.cns_profile", "aws_nat_gateway.ngw1"]
  ami           = data.aws_ami.cnp_ami.id
  instance_type = var.types.cnp
  key_name      = var.key_pair
  iam_instance_profile = aws_iam_instance_profile.cns_profile.name

  network_interface {
    network_interface_id = aws_network_interface.cnp1_mgmt.id
    device_index         = 0
  }

  network_interface {
    network_interface_id = aws_network_interface.cnp1_1a.id
    device_index         = 1
  }

  network_interface {
    network_interface_id = aws_network_interface.cnp1_1b.id
    device_index         = 2
  }

  user_data = <<EOF
# -- START VTPS CLOUDWATCH
log-group-name ${var.log_group_name}
# -- END VTPS CLOUDWATCH
# -- START VTPS CLI
edit
virtual-segments
virtual-segment "cloud formation"
exit
commit
exit
high-availability
cloudwatch-health period 60
commit
exit
log
cloudwatch log-group-name ${var.log_group_name}
cloudwatch inspection-event enable
cloudwatch ips-event enable
exit
commit
exit
save-config -y
cloudone register ${var.c1_api_key}
# -- END VTPS CLI
EOF
    tags = {
    Name = format("%s - %s", var.unique_id, "CNS1 Instance")
    Description = "Cloud One Network Security Instance"
    }
}
#Interfaces for cnp2
resource "aws_network_interface" "cnp2_mgmt" {
    subnet_id       = aws_subnet.inet_mgmt_sub2.id
    security_groups = [aws_security_group.inet_mgmt_sg.id]

    tags = {
    Name        = "CNP2 Mangement Interface"
    Description = "Cloud One Network Security Management Interface"
    }
}
resource "aws_network_interface" "cnp2_1a" {
    subnet_id         = aws_subnet.inet_prot_sub2.id
    security_groups   = [aws_security_group.inet_ips_sg.id]
    source_dest_check = false

    tags = {
    Name        = "CNP2 Interface 1A"
    Description = "Cloud One Network Security Inspection Interface 1A"
    }
}
resource "aws_network_interface" "cnp2_1b" {
    subnet_id         = aws_subnet.inet_pub_sub2.id
    security_groups   = [aws_security_group.inet_ips_sg.id]
    source_dest_check = false

    tags = {
    Name        = "CNP2 Interface 1B"
    Description = "Cloud One Network Security Sanitized Interface 1B"
    }
}
#CNS instance 2
resource "aws_instance" "cnp2" {
  depends_on = ["aws_iam_instance_profile.cns_profile", "aws_nat_gateway.ngw1"]
  ami                  = data.aws_ami.cnp_ami.id
  instance_type        = var.types.cnp
  key_name             = var.key_pair
  iam_instance_profile = aws_iam_instance_profile.cns_profile.name

  network_interface {
  network_interface_id = aws_network_interface.cnp2_mgmt.id
  device_index         = 0
  }

  network_interface {
  network_interface_id = aws_network_interface.cnp2_1a.id
  device_index         = 1
  }

  network_interface {
  network_interface_id = aws_network_interface.cnp2_1b.id
  device_index         = 2
  }

  tags = {
  Name = format("%s - %s", var.unique_id, "CNS2 Instance")
  Description = "Cloud One Network Security Instance"
  }

  user_data = <<EOF
# -- START VTPS CLOUDWATCH
log-group-name ${var.log_group_name}
# -- END VTPS CLOUDWATCH
# -- START VTPS CLI
edit
virtual-segments
virtual-segment "cloud formation"
exit
commit
exit
high-availability
cloudwatch-health period 60
commit
exit
log
cloudwatch log-group-name ${var.log_group_name}
cloudwatch inspection-event enable
cloudwatch ips-event enable
exit
commit
exit
save-config -y
cloudone register ${var.c1_api_key}
# -- END VTPS CLI
EOF
}

####HA and Health Monitoring failover
#Create SNS Topic
resource "aws_sns_topic" "nsva_health" {
  name = format("%s-%s", var.unique_id, "NSVA_health_sns")
}

####OUTPUTS####
output "bastion1_public_ip" {
  value = aws_eip.bastion1_eip.public_ip
}
output "bastion1_private_ip" {
  value = aws_instance.bastion_host1.private_ip
}
output "attacker_public_ip" {
  value = aws_eip.attacker_eip.public_ip
}
output "attacker_website" {
  value = format("http://%s:5000", aws_eip.attacker_eip.public_ip)
}
output "workload1_public_ip" {
  value = aws_eip.work1_eip.public_ip
}
output "workload1_vulnerable_webite" {
  value = format("http://%s", aws_eip.work1_eip.public_ip)
}
output "cnp1_mgmt_ip" {
  value = aws_network_interface.cnp1_mgmt.private_ip
}
output "cnp2_mgmt_ip" {
  value = aws_network_interface.cnp2_mgmt.private_ip
}
