variable "demo_cidrs" {
  type        = list(string)
  description = "/24 CIDR ranges to use for the Network Security demo VPCs."
}

variable "demo_tags" {
  type        = map(string)
  description = "map of common tags used when creating all resources"
}

variable "demo_azs" {
  type        = list(string)
  description = "List of availability zones to use"
}

variable "struts_port" {
  type        = string 
  description = "Listening port for vulnerable Apache Struts"
  default     = "80"
}

variable "flask_port" {
  type        = string 
  description = "Listening port for Flask attack server"
  default     = "5000"
}

variable "my_pub_ip" {
  type        = string
  description = "your public IP"
}