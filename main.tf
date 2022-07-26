# Transit VPC with firenet enabled
module "firenet" {
  source  = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version = "2.1.2"

  cloud                  = "AWS"
  cidr                   = var.cidr
  region                 = var.region
  account                = var.aws_acct_name
  ha_gw                  = false
  enable_transit_firenet = true
  instance_size          = "c5.xlarge"
  name                   = "avx-${var.env_name}"
}

# Get the Transit GW LAN interface IP
data "aws_network_interface" "trans_gw" {
  filter {
    name   = "tag:Name"
    values = ["Aviatrix-eni@${module.firenet.transit_gateway.gw_name}_eth2"]
  }
  depends_on = [
    module.firenet
  ]
}

# Get the LAN subnet
data "aws_subnet_ids" "subnet" {
  vpc_id = module.firenet.vpc.vpc_id
  filter {
    name   = "tag:Name"
    values = ["*-dmz-firewall"]
  }
  depends_on = [
    module.firenet
  ]
}

# Deploy the Firewall
module "fw" {
  source = "git::https://github.com/fkhademi/terraform-aws-instance-module.git?ref=v1.5-firenet"

  name          = "${var.env_name}-fw"
  region        = var.region
  vpc_id        = module.firenet.vpc.vpc_id
  subnet_id     = module.firenet.vpc.public_subnets[0].subnet_id
  ssh_key       = var.ssh_key
  public_ip     = true
  instance_size = "t3.large"
  user_data     = templatefile("${path.module}/cloud-init.tpl", {
    hostname  = "fw.${var.domain_name}",
    gw_lan_ip = data.aws_network_interface.trans_gw.private_ip,
    pod_id    = "20"
  })
}

# Additional LAN interface for the FW
resource "aws_network_interface" "lan" {
  subnet_id         = element(tolist(data.aws_subnet_ids.subnet.ids), 0)
  security_groups   = [module.fw.sg.id]
  source_dest_check = false

  attachment {
    instance     = module.fw.vm.id
    device_index = 1
  }
}

# Associate FW with Firenet
resource "aviatrix_firewall_instance_association" "fw" {
  vpc_id               = module.firenet.vpc.vpc_id
  firenet_gw_name      = module.firenet.transit_gateway.gw_name
  instance_id          = module.fw.vm.id
  firewall_name        = "fw"
  lan_interface        = aws_network_interface.lan.id
  management_interface = null
  egress_interface     = module.fw.vm.primary_network_interface_id
  attached             = true
}

# Create Firenet
resource "aviatrix_firenet" "firenet" {
  vpc_id                               = module.firenet.vpc.vpc_id
  inspection_enabled                   = true
  egress_enabled                       = false
  keep_alive_via_lan_interface_enabled = true
  manage_firewall_instance_association = false
  depends_on                           = [aviatrix_firewall_instance_association.fw]
}
