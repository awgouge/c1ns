variable "cidr" {
    type        = string
    description = "/24 CIDR range to use for the Network Security VPC"
}

variable "region" {
    type        = string
    description = "Target AWS Region"
}

variable "user" {
    type        = string 
    description = "User that is deploying the environment"
}

variable "stage" {
    type        = string 
    description = "production|staging|develop"
}

variable "api_key" {
  type        = string
  description = "API key to register the instances with Cloud One Network Security"
}

variable "my_pub_ip" {
  type        = string
  description = "your public IP"
}