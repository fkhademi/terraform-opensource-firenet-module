variable "cidr" { 
    description = "CIDR range for the Transit Firenet VPC"
    default = "10.20.0.0/16"
}

variable "region" { 
    description = "AWS Region to deploy the resources"
    default = "eu-central-1"
}

variable "env_name" { 
    description = "Name of the environment"
    default = "firenet"
}

variable "domain_name" { 
    description = "Domain name for the virtual hosts"
    default = "avxlab.de" 
}

variable "fw_hostname" {
    description = "Hostname of the FW instance"
    default = "fw"
}

variable "aws_acct_name" { 
    description = "AWS account name as defined in the Aviatrix Controller"
    default = "aws" 
}

variable "ssh_key" {
    description = "SSH key for the firewall instance"
}