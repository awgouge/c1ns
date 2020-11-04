variable "nsvpc_cidr" {
  type        = string
  description = "/24 CIDR range to use for the Network Security VPC"
}

variable "nsvpc_name" {
  type        = string
  description = "Name tag value to use when creating the VPC"
  default     = "NetworkSecurityVPC"
}

variable "nsvpc_tags" {
  type        = map(string)
  description = "map of common tags used when creating all resources"
}

variable "nsvpc_azs" {
  type        = list(string)
  description = "List of availability zones to use"
}

variable "tgw_id" {
  type        = string
  description = "ID of existing TGW"
}

variable "register_api_key" {
  type        = string
  description = "API key to register the instances with Cloud One Network Security"
}

variable "nsva_instance_type" {
  type        = string
  description = "NSVA instance type"
  default = "c5.2xlarge"
}

variable enable_lambda {
  description = "Enable/disable HA Lambda"
  type        = bool
  default     = true
}

variable nsva_build {
  description = "NSVA Build to use"
  default     = "2020.10.0.10702"
}

variable nsva_failover {
  description = "Failover to second AZ?  Defaults to false which fails open by routing traffic back to the TGW"
  type        = bool
  default     = false
}
