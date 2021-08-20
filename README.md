# terraform-opensource-firenet-module
Module to deploy an Aviatrix Transit FireNet with an Open Source Firewall

### Usage
```
module "firenet" {
  source  = "git::https://github.com/fkhademi/terraform-opensource-firenet-module.git"
  ssh_key = var.ssh_key
}
```

### Variables
The following variables can be used:

key | value | default
--- | --- | ---
region | AWS region to deploy the Egress VPC in | eu-central-1
aws_account_name | The AWS accountname on the Aviatrix controller, under which the controller will deploy this VPC | AWS
cidr | The IP CIDR to be used to create the VPC. | 10.200.0.0/16
env_name | Name of the VPC and Gateway | firenet
domain_name | DNS domain to be used | avxlab.de
fw_hostname | Hostname for the firewall VM | fw
ssh_key | SSH public key for the Firewall VM | REQUIRED