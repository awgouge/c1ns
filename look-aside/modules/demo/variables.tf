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